/// Flame - A lightweight web framework for Flix with effect polymorphism

mod Flame {

    // Type Aliases

    pub type alias ContentType = String
    pub type alias Body = String
    pub type alias Method = String
    pub type alias Path = String
    pub type alias Pattern = String
    pub type alias Port = Int32
    pub type alias NanoTime = Int64
    pub type alias Params = Map[String, String]
    pub type alias MiddlewareName = String

    // Core Types

    /// HTTP Response
    pub enum Response {
        case Response(ContentType, Body)
    }

    /// Route definition with effect polymorphism
    pub enum Route[ef: Eff] {
        case Get(Pattern, Unit -> Response \ ef)
        case Post(Pattern, Body -> Response \ ef)
        case GetParam(Pattern, Params -> Response \ ef)
        case PostParam(Pattern, (Params, Body) -> Response \ ef)
    }

    /// Phantom types for server state
    pub enum NoServer
    pub enum WithServer

    /// Internal app data
    pub enum AppData[ef: Eff] {
        case AppData(Port, List[Route[ef]], List[MiddlewareName])
    }

    /// Server implementation type
    pub type alias ServerImpl[ef: Eff] = AppData[ef] -> Unit \ { IO, Chan, NonDet, Logger, ef }

    /// App with phantom type for state tracking
    pub enum App[_s: Type, ef: Eff] {
        case App(AppData[ef], Option[ServerImpl[ef]])
    }

    /// Route matching result
    pub enum RouteMatch[ef: Eff] {
        case NotFound
        case MatchedGet(Unit -> Response \ ef)
        case MatchedPost(Body -> Response \ ef)
        case MatchedGetParam(Params -> Response \ ef, Params)
        case MatchedPostParam((Params, Body) -> Response \ ef, Params)
    }

    /// Request context
    pub enum Context {
        case Context(Method, Path, NanoTime)
    }

    pub def context(method: Method, path: Path, startTime: NanoTime): Context =
        Context.Context(method, path, startTime)

    pub def getCtxMethod(ctx: Context): Method = match ctx {
        case Context.Context(m, _, _) => m
    }

    pub def getCtxPath(ctx: Context): Path = match ctx {
        case Context.Context(_, p, _) => p
    }

    pub def getCtxStartTime(ctx: Context): NanoTime = match ctx {
        case Context.Context(_, _, t) => t
    }

    /// Effect for HTTP request/response handling
    pub eff FlameHandler {
        def readBody(): String
        def sendResponse(response: Response): Unit
        def send404(): Unit
    }

    /// Effect for middleware hooks
    pub eff MiddlewareHook {
        def onRequest(ctx: Context): Unit
        def onResponse(ctx: Context, response: Response): Unit
    }

    /// Effect for logging
    pub eff Logger {
        def logRequest(ctx: Context): Unit
        def logResponse(ctx: Context, response: Response): Unit
    }

    /// Create a new App (NoServer state)
    pub def app(): App[NoServer, {}] =
        App.App(AppData.AppData(8080, Nil, Nil), None)

    /// Set port
    pub def port(p: Port, a: App[s, ef]): App[s, ef] = match a {
        case App.App(AppData.AppData(_, routes, mws), srv) =>
            App.App(AppData.AppData(p, routes, mws), srv)
    }

    /// Register GET route
    pub def get(pattern: Pattern, h: Unit -> Response \ ef1, a: App[s, ef2]): App[s, ef1 + ef2] = match a {
        case App.App(AppData.AppData(p, routes, mws), srv) =>
            let newRoute: Route[ef1 + ef2] = Route.Get(pattern, upcastHandler0(h));
            let newRoutes: List[Route[ef1 + ef2]] = newRoute :: upcastRoutes(routes);
            App.App(AppData.AppData(p, newRoutes, mws), upcastServerImpl(srv))
    }

    /// Register POST route
    pub def post(pattern: Pattern, h: Body -> Response \ ef1, a: App[s, ef2]): App[s, ef1 + ef2] = match a {
        case App.App(AppData.AppData(p, routes, mws), srv) =>
            let newRoute: Route[ef1 + ef2] = Route.Post(pattern, upcastHandler1(h));
            let newRoutes: List[Route[ef1 + ef2]] = newRoute :: upcastRoutes(routes);
            App.App(AppData.AppData(p, newRoutes, mws), upcastServerImpl(srv))
    }

    /// Register GET route with URL parameters
    pub def getParam(pattern: Pattern, h: Params -> Response \ ef1, a: App[s, ef2]): App[s, ef1 + ef2] = match a {
        case App.App(AppData.AppData(p, routes, mws), srv) =>
            let newRoute: Route[ef1 + ef2] = Route.GetParam(pattern, upcastHandler1(h));
            let newRoutes: List[Route[ef1 + ef2]] = newRoute :: upcastRoutes(routes);
            App.App(AppData.AppData(p, newRoutes, mws), upcastServerImpl(srv))
    }

    /// Register POST route with URL parameters
    pub def postParam(pattern: Pattern, h: (Params, Body) -> Response \ ef1, a: App[s, ef2]): App[s, ef1 + ef2] = match a {
        case App.App(AppData.AppData(p, routes, mws), srv) =>
            let newRoute: Route[ef1 + ef2] = Route.PostParam(pattern, upcastHandler2(h));
            let newRoutes: List[Route[ef1 + ef2]] = newRoute :: upcastRoutes(routes);
            App.App(AppData.AppData(p, newRoutes, mws), upcastServerImpl(srv))
    }

    // Effect upcasting helpers

    def upcastHandler0(h: Unit -> Response \ ef1): Unit -> Response \ { ef1, ef2 } =
        _ -> unchecked_cast(h() as _ \ { ef1, ef2 })

    def upcastHandler1(h: a -> Response \ ef1): a -> Response \ { ef1, ef2 } =
        x -> unchecked_cast(h(x) as _ \ { ef1, ef2 })

    def upcastHandler2(h: (a, b) -> Response \ ef1): (a, b) -> Response \ { ef1, ef2 } =
        (x, y) -> unchecked_cast(h(x, y) as _ \ { ef1, ef2 })

    def upcastRoutes(routes: List[Route[ef1]]): List[Route[ef1 + ef2]] =
        List.map(r -> upcastRoute(r), routes)

    def upcastRoute(r: Route[ef1]): Route[ef1 + ef2] = match r {
        case Route.Get(p, h) => Route.Get(p, upcastHandler0(h))
        case Route.Post(p, h) => Route.Post(p, upcastHandler1(h))
        case Route.GetParam(p, h) => Route.GetParam(p, upcastHandler1(h))
        case Route.PostParam(p, h) => Route.PostParam(p, upcastHandler2(h))
    }

    def upcastServerImpl(srv: Option[ServerImpl[ef1]]): Option[ServerImpl[ef1 + ef2]] =
        Option.map(impl -> data -> unchecked_cast(impl(upcastAppDataDown(data)) as _ \ { IO, Chan, NonDet, Logger, ef1, ef2 }), srv)

    def upcastAppDataDown(data: AppData[ef1 + ef2]): AppData[ef1] = match data {
        case AppData.AppData(p, routes, mws) =>
            AppData.AppData(p, List.map(r -> downcastRoute(r), routes), mws)
    }

    def downcastRoute(r: Route[ef1 + ef2]): Route[ef1] = match r {
        case Route.Get(p, h) => Route.Get(p, _ -> unchecked_cast(h() as _ \ ef1))
        case Route.Post(p, h) => Route.Post(p, x -> unchecked_cast(h(x) as _ \ ef1))
        case Route.GetParam(p, h) => Route.GetParam(p, x -> unchecked_cast(h(x) as _ \ ef1))
        case Route.PostParam(p, h) => Route.PostParam(p, (x, y) -> unchecked_cast(h(x, y) as _ \ ef1))
    }

    /// Enable logger middleware
    pub def useLogger(a: App[s, ef]): App[s, ef] = match a {
        case App.App(AppData.AppData(p, routes, mws), srv) =>
            App.App(AppData.AppData(p, routes, "logger" :: mws), srv)
    }

    /// Set server implementation (transitions to WithServer state)
    pub def server(impl: ServerImpl[ef], a: App[_s, ef]): App[WithServer, ef] = match a {
        case App.App(data, _) => App.App(data, Some(impl))
    }

    pub def hasLogger(a: App[s, ef]): Bool =
        List.memberOf("logger", getMiddlewares(a))

    /// Create text response
    pub def text(body: String): Response =
        Response.Response("text/plain; charset=UTF-8", body)

    /// Create JSON response
    pub def json(body: String): Response =
        Response.Response("application/json; charset=UTF-8", body)

    def mapToJson(m: Params): Body =
        let pairs = Map.toList(m) |> List.map(kv -> {
            let (k, v) = kv;
            "\"${k}\": \"${v}\""
        });
        "{" + String.intercalate(", ", pairs) + "}"

    /// Create JSON response from Map
    pub def jsonMap(m: Params): Response =
        Response.Response("application/json; charset=UTF-8", mapToJson(m))

    def splitPath(s: String): List[String] =
        String.split({regex = "/"}, s) |> List.filter(x -> x != "")

    /// Match pattern against path, extracting parameters
    /// e.g., matchPattern("/entry/:id", "/entry/123") => Some(Map#{"id" => "123"})
    def matchPattern(pattern: Pattern, path: Path): Option[Params] =
        let patternParts = splitPath(pattern);
        let pathParts = splitPath(path);
        matchParts(patternParts, pathParts, Map.empty())

    def matchParts(patternParts: List[String], pathParts: List[String], acc: Params): Option[Params] =
        match (patternParts, pathParts) {
            case (Nil, Nil) => Some(acc)
            case (Nil, _) => None
            case (_, Nil) => None
            case (p :: ps, v :: vs) =>
                if (String.startsWith({prefix = ":"}, p)) {
                    let paramName = String.dropLeft(1, p);
                    matchParts(ps, vs, Map.insert(paramName, v, acc))
                } else if (p == v) {
                    matchParts(ps, vs, acc)
                } else {
                    None
                }
        }

    /// Find matching route
    pub def findRoute(method: Method, path: Path, routes: List[Route[ef]]): RouteMatch[ef] =
        match routes {
            case Nil => RouteMatch.NotFound
            case Route.Get(pattern, response) :: rest =>
                if (method == "GET" and pattern == path) {
                    RouteMatch.MatchedGet(response)
                } else {
                    findRoute(method, path, rest)
                }
            case Route.Post(pattern, h) :: rest =>
                if (method == "POST" and pattern == path) {
                    RouteMatch.MatchedPost(h)
                } else {
                    findRoute(method, path, rest)
                }
            case Route.GetParam(pattern, h) :: rest =>
                if (method == "GET") {
                    match matchPattern(pattern, path) {
                        case Some(params) => RouteMatch.MatchedGetParam(h, params)
                        case None => findRoute(method, path, rest)
                    }
                } else {
                    findRoute(method, path, rest)
                }
            case Route.PostParam(pattern, h) :: rest =>
                if (method == "POST") {
                    match matchPattern(pattern, path) {
                        case Some(params) => RouteMatch.MatchedPostParam(h, params)
                        case None => findRoute(method, path, rest)
                    }
                } else {
                    findRoute(method, path, rest)
                }
        }

    /// Handle request using FlameHandler effect
    pub def handleRequest(method: Method, path: Path, routes: List[Route[ef]]): Unit \ { FlameHandler, ef } =
        match findRoute(method, path, routes) {
            case RouteMatch.NotFound => FlameHandler.send404()
            case RouteMatch.MatchedGet(h) => FlameHandler.sendResponse(h())
            case RouteMatch.MatchedPost(h) =>
                let body = FlameHandler.readBody();
                FlameHandler.sendResponse(h(body))
            case RouteMatch.MatchedGetParam(h, params) =>
                FlameHandler.sendResponse(h(params))
            case RouteMatch.MatchedPostParam(h, params) =>
                let body = FlameHandler.readBody();
                FlameHandler.sendResponse(h(params, body))
        }

    /// Run with actual logging
    pub def withLoggerHandler(f: Unit -> Unit \ { IO, Logger, ef }): Unit \ { IO, ef } =
        run {
            f()
        } with handler Logger {
            def logRequest(ctx, resume) = {
                let m = getCtxMethod(ctx);
                let p = getCtxPath(ctx);
                println("[${m}] ${p} --> Request");
                resume()
            }
            def logResponse(ctx, response, resume) = {
                let m = getCtxMethod(ctx);
                let p = getCtxPath(ctx);
                let Response.Response(contentType, _) = response;
                println("[${m}] ${p} <-- ${contentType}");
                resume()
            }
        }

    /// Run without logging (no-op handler)
    pub def withNoOpLogger(f: Unit -> Unit \ { Logger, ef }): Unit \ ef =
        run {
            f()
        } with handler Logger {
            def logRequest(_, resume) = resume()
            def logResponse(_, _, resume) = resume()
        }

    /// Start server (only available in WithServer state)
    pub def fire(a: App[WithServer, ef]): Unit \ { IO, Chan, NonDet, ef } = match a {
        case App.App(data, Some(impl)) =>
            if (dataHasLogger(data)) {
                withLoggerHandler(_ -> impl(data))
            } else {
                withNoOpLogger(_ -> impl(data))
            }
        case App.App(_, None) => ()
    }

    // Accessors

    pub def getPort(a: App[s, ef]): Port = match a {
        case App.App(AppData.AppData(p, _, _), _) => p
    }

    pub def getRoutes(a: App[s, ef]): List[Route[ef]] = match a {
        case App.App(AppData.AppData(_, routes, _), _) => routes
    }

    pub def getMiddlewares(a: App[s, ef]): List[MiddlewareName] = match a {
        case App.App(AppData.AppData(_, _, mws), _) => mws
    }

    pub def getDataPort(d: AppData[ef]): Port = match d {
        case AppData.AppData(p, _, _) => p
    }

    pub def getDataRoutes(d: AppData[ef]): List[Route[ef]] = match d {
        case AppData.AppData(_, routes, _) => routes
    }

    pub def getDataMiddlewares(d: AppData[ef]): List[MiddlewareName] = match d {
        case AppData.AppData(_, _, mws) => mws
    }

    pub def dataHasLogger(d: AppData[ef]): Bool =
        List.memberOf("logger", getDataMiddlewares(d))

    /// Handle request with middleware hooks
    pub def handleRequestWithMiddleware(ctx: Context, routes: List[Route[ef]]): Response \ { FlameHandler, MiddlewareHook, ef } =
        MiddlewareHook.onRequest(ctx);
        let method = getCtxMethod(ctx);
        let path = getCtxPath(ctx);
        let response = match findRoute(method, path, routes) {
            case RouteMatch.NotFound =>
                FlameHandler.send404();
                Response.Response("text/plain; charset=UTF-8", "Not Found")
            case RouteMatch.MatchedGet(h) =>
                let r = h();
                FlameHandler.sendResponse(r);
                r
            case RouteMatch.MatchedPost(h) =>
                let body = FlameHandler.readBody();
                let r = h(body);
                FlameHandler.sendResponse(r);
                r
            case RouteMatch.MatchedGetParam(h, params) =>
                let r = h(params);
                FlameHandler.sendResponse(r);
                r
            case RouteMatch.MatchedPostParam(h, params) =>
                let body = FlameHandler.readBody();
                let r = h(params, body);
                FlameHandler.sendResponse(r);
                r
        };
        MiddlewareHook.onResponse(ctx, response);
        response

}
