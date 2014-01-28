// wot vcl

// Backends for all of the various services

backend rabbitmq { .host = "127.0.0.1"; .port = "15672"; }
backend pgproc { .host = "127.0.0.1"; .port = "5555"; }
backend visage { .host = "127.0.0.1"; .port = "9292"; }
backend pdns { .host = "127.0.0.1"; .port = "8053"; }
backend www { .host = "127.0.0.1"; .port = "8080"; }
backend websockets { .host = "127.0.0.1"; .port = "8088"; }


// Code for routing requests

sub vcl_recv {
	if (req.url ~ "^/$") {
		set req.url = "/wot.html";
		set req.backend = www;
	} elsif (req.url ~ "^/api/") {
		set req.backend = rabbitmq;
		return(pass);
	} elsif (req.url ~ "^/rabbitmq/") {
		set req.url = regsub(req.url,"^/rabbitmq/","/");
		set req.backend = rabbitmq;
		return(pass);
	} elsif (req.url ~ "^/dns/") {
		set req.url = regsub(req.url,"^/dns/","/");
		set req.backend = pgproc;
		return(pass);
	} elsif (req.url ~ "^/dns-admin/") {
		set req.url = regsub(req.url,"^/dns-admin/","/");
		set req.backend = pdns;
		return(pass);
	} elsif (req.url ~ "^/stream/") {
		set req.url = regsub(req.url,"^/stream/","/");
		set req.backend = websockets;
		return(pipe);
	} else {
		set req.backend = www;
	}
}

// Code for rewriting backend requests

sub vcl_fetch {

	// Add some debugging for how varnish is caching requests
	if (! beresp.ttl > 0s) {
		set beresp.http.X-Cacheable = "NO:Not Cacheable";
		return(deliver);
	} elsif (req.http.Cookie ~ "(UserID|_session)") {
		set beresp.http.X-Cacheable = "NO:Got Session";
		return(deliver);
	} elsif (beresp.http.Cache-Control ~ "private") {
		set beresp.http.X-Cacheable = "NO:Cache-Control=private";
		return(deliver);
	} elsif (beresp.ttl < 1s) {
		set beresp.ttl = 60s;
		set beresp.grace = 60s;
		set beresp.http.X-Cacheable = "YES:FORCED";
	} else {
		set beresp.http.X-Cacheable = "YES";
	}
}

// Code for rewriting responses

sub vcl_deliver {
	return(deliver);
}

// Code for delivering error messages
sub vcl_error {
	if (obj.status == 201) {
		set obj.http.Location = req.http.X-Location;
		return(deliver);
	}
	if (obj.status == 200) {
		synthetic "OK";
		return(deliver);
	}
	if (obj.status == 204) {
		return(deliver);
	}	
	synthetic {
		// Todo generate a custom error page
		"These are not the droids you are looking for"
	};
	return(deliver);
}



