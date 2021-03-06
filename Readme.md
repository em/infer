Infer
====================
Infer (i) is a command line utility for rapidly opening files based on keyword ranks. If the closest match is higher than a degree of certainty (default 10%) the file will be opened in your configured editor (default vim).

```
$ i -h
Usage: i [options] keywords...

Options:
    -m, --max [num]                  Limit number of results
    -t, --technique [mdfind|grep]    Search technique to use
    -s, --[no-]showonly              Show results and never open the inference
    -a, --all                        Do not truncate the results
        --[no-]prompt                Prompt for result selection
    -p, --plain                      Plain filename output; no indices, ranks, prompting, or unnecessary info.
    -z, --null                       Separate results with a null character instead of newline.
    -g, --global                     Global filesystem search
    -c, --command [COMMAND]          Execute command on inference
    -v, --[no-]verbose               Verbose output
    -[0-9], --index                  Force open result n
    -h, --help                       Show this message
```

Installation
====================
```
curl -L http://github.com/em/infer/raw/master/infer.rb -o /usr/local/bin/i && chmod +x !#:4
```

Example
====================

Infer with a search for "http" run against the node.js source code:
<pre>
i http -sa
 0. ██████████▏lib/http.js 
 1. █████████▎ lib/https.js 
 2. ███████▍   deps/http_parser/http_parser.c 
 3. ██████▌    deps/http_parser/ 
 4. █████▎     doc/api/api/http.html 
 5. █████▏     doc/api/api/https.html 
 6. ████▉      deps/http_parser/test.c 
 7. ████▋      benchmark/http_simple.js 
 8. ████▌      deps/http_parser/Makefile 
 9. ████▎      deps/http_parser/README.md 
10. ████       deps/http_parser/LICENSE-MIT 
11. ███▉       test/simple/test-http-wget.js 
12. ███▊       benchmark/http_simple_bench.sh 
13. ███▋       benchmark/static_http_server.js 
14. ███▌       test/simple/test-http-chunked.js 
15. ███▍       test/disabled/test-http-agent2.js 
16. ███▎       test/simple/test-http-exceptions.js 
17. ███▏       test/simple/test-http-client-race.js 
18. ███        test/simple/test-http-abort-client.js 
19. ███        test/simple/test-http-buffer-sanity.js 
20. ██▉        test/disabled/test-http-head-request.js 
21. ██▉        test/pummel/test-https-large-response.js 
22. ██▊        test/simple/test-http-default-encoding.js 
23. ██▋        test/disabled/test-https-loop-to-google.js 
24. ██▋        test/simple/test-http-client-parse-error.js 
25. ██▋        test/simple/test-http-server-multiheaders.js 
26. ██▌        test/pummel/test-http-client-reconnect-bug.js 
27. ██▌        test/disabled/test-http-big-proxy-responses.js 
28. ██▍        test/simple/test-http-allow-req-after-204-res.js 
29. ██▎        test/simple/test-http-head-response-has-no-body.js 
30. ██▎        test/simple/test-http-keep-alive-close-on-header.js 
31. ██▏        test/simple/test-http-many-keep-alive-connections.js 
</pre>

The options -sa are "show only" and "all results".
You'll notice in these results lib/http.js is significantly higher than the proceeding pathname.
Enough that simply running <pre>i http</pre> would immediately open it your configured editor.

Now, if I wanted `deps/http_parser/http_parser.c` all I have to do is make it less ambiguous:
```
i http .c
```
This is enough to boost http_parser.c past the other results and open it immediately.

Configuration
====================
Example ~/.infrc
<pre>
inference_index: 0.1  # Open if first result is 10% better than the next

# Regexes used to classify files by name
matchers:
  scalar_graphics: "\\.(psg|png|jpeg|jpg|gif|tiff)$"
  vector_graphics: "\\.(ai|eps)$"

# Commands that get executed on an inference, $ holds the full file name
handlers:
  scalar_graphics: "open -a \"Adobe Photoshop CS5\" $"
  vector_graphics: "open -a \"Adobe Illustrator CS5\" $"
  default: "vim $"  # Catch-all if nothing else is matched (make this your most general-purpose editor, e.g. mate)
</pre>

# Pro tip
```
I <command> keywords
^ capitalize to specify a command explicitly

I use this all the time to open html instead of edit it:
I open index.html
```
