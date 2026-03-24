/// FlameJava - Java HttpServer implementation for Flame

mod Flame.Java {
    import com.sun.net.httpserver.HttpServer
    import com.sun.net.httpserver.HttpHandler
    import com.sun.net.httpserver.HttpExchange
    import java.net.InetSocketAddress
    import java.lang.Runnable
    import java.lang.Runtime
    import java.lang.Thread
    import java.lang.System
    import java.io.InputStreamReader
    import java.io.BufferedReader

    use Flame.App
    use Flame.AppData
    use Flame.Response
    use Flame.Route
    use Flame.Context
    use Flame.FlameHandler
    use Flame.MiddlewareHook
    use Flame.WithServer

    /// Set Java HttpServer (transitions to WithServer state)
    pub def javaServer(a: App[s, ef]): App[WithServer, ef] =
        Flame.server(runHttpServer, a)

    def currentTimeNanos(): Int64 \ IO = System.nanoTime()

    def sendResponseImpl(exchange: HttpExchange, response: Response): Unit \ IO =
        let Response.Response(contentType, body) = response;
        let responseBytes = body.getBytes();
        exchange.getResponseHeaders().set("Content-Type", contentType);
        exchange.sendResponseHeaders(200, responseBytes |> Array.length |> Int32.toInt64);
        let os = exchange.getResponseBody();
        os.write(responseBytes);
        os.close()

    def send404Impl(exchange: HttpExchange): Unit \ IO =
        let body = "Not Found";
        let responseBytes = body.getBytes();
        exchange.getResponseHeaders().set("Content-Type", "text/plain; charset=UTF-8");
        exchange.sendResponseHeaders(404, responseBytes |> Array.length |> Int32.toInt64);
        let os = exchange.getResponseBody();
        os.write(responseBytes);
        os.close()

    def readBodyImpl(exchange: HttpExchange): String \ IO =
        region rc {
            let is = exchange.getRequestBody();
            let reader = new BufferedReader(new InputStreamReader(is));
            let sb = StringBuilder.empty(rc);
            def loop(): Unit \ { rc, IO } = {
                let line = reader.readLine();
                if (Object.isNull(line)) {
                    ()
                } else {
                    StringBuilder.appendString(line, sb);
                    loop()
                }
            };
            loop();
            reader.close();
            StringBuilder.toString(sb)
        }

    /// Handle request with logger middleware
    def handleWithLogger(exchange: HttpExchange, ctx: Context, routes: List[Route[ef]]): Unit \ { IO, ef } =
        run {
            run {
                Flame.handleRequestWithMiddleware(ctx, routes)
            } with handler FlameHandler {
                def readBody(_, resume) = {
                    let b = readBodyImpl(exchange);
                    resume(b)
                }
                def sendResponse(response, resume) = {
                    sendResponseImpl(exchange, response);
                    resume()
                }
                def send404(_, resume) = {
                    send404Impl(exchange);
                    resume()
                }
            }
        } with handler MiddlewareHook {
            def onRequest(reqCtx, resume) = {
                let m = Flame.getCtxMethod(reqCtx);
                let p = Flame.getCtxPath(reqCtx);
                println("[${m}] ${p} --> Request");
                resume()
            }
            def onResponse(reqCtx, response, resume) = {
                let m = Flame.getCtxMethod(reqCtx);
                let p = Flame.getCtxPath(reqCtx);
                let endTime = currentTimeNanos();
                let start = Flame.getCtxStartTime(reqCtx);
                let durationMs = (endTime - start) / 1000000i64;
                let Response.Response(contentType, _) = response;
                println("[${m}] ${p} <-- ${contentType} (${durationMs}ms)");
                resume()
            }
        }

    /// Handle request without middleware
    def handleWithoutMiddleware(exchange: HttpExchange, ctx: Context, routes: List[Route[ef]]): Unit \ { IO, ef } =
        run {
            run {
                Flame.handleRequestWithMiddleware(ctx, routes)
            } with handler FlameHandler {
                def readBody(_, resume) = {
                    let b = readBodyImpl(exchange);
                    resume(b)
                }
                def sendResponse(response, resume) = {
                    sendResponseImpl(exchange, response);
                    resume()
                }
                def send404(_, resume) = {
                    send404Impl(exchange);
                    resume()
                }
            }
        } with handler MiddlewareHook {
            def onRequest(_, resume) = resume()
            def onResponse(_, _, resume) = resume()
        }

    /// Run HTTP server
    def runHttpServer(a: AppData[ef]): Unit \ { IO, Chan, NonDet, ef } = unchecked_cast({
        let appPort = Flame.getDataPort(a);
        let routes = Flame.getDataRoutes(a);
        let loggerEnabled = Flame.dataHasLogger(a);
        let server = HttpServer.create(new InetSocketAddress(appPort), 0);

        server.createContext("/", new HttpHandler {
            def $handle(_this: HttpHandler, exchange: HttpExchange): Unit \ IO =
                unchecked_cast({
                    let path = exchange.getRequestURI().getPath();
                    let method = exchange.getRequestMethod();
                    let startTime = currentTimeNanos();
                    let ctx = Flame.context(method, path, startTime);
                    if (loggerEnabled) {
                        handleWithLogger(exchange, ctx, routes)
                    } else {
                        handleWithoutMiddleware(exchange, ctx, routes)
                    }
                } as _ \ IO)
        });

        server.start();
        println("Server running on http://localhost:${appPort}");

        // Wait for shutdown signal
        let (tx, rx) = Channel.buffered(1);
        Runtime.getRuntime().addShutdownHook(new Thread(
            new Runnable {
                def $run(_this: Runnable): Unit \ Chan = {
                    region rc {
                        spawn Channel.send((), tx) @ rc
                    }
                }
            })
        );

        Channel.recv(rx);
        println("Server exiting gracefully");
        server.stop(0)
    } as _ \ { IO, Chan, NonDet, ef })

}
