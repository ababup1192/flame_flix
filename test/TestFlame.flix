// Tests for Flame

// Response tests
@Test
def testText01(): Unit \ Assert =
    let r = Flame.text("Hello");
    let Flame.Response.Response(ct, body) = r;
    Assert.assertEq(expected = "text/plain; charset=UTF-8", ct);
    Assert.assertEq(expected = "Hello", body)

@Test
def testJson01(): Unit \ Assert =
    let r = Flame.json("{\"key\": \"value\"}");
    let Flame.Response.Response(ct, body) = r;
    Assert.assertEq(expected = "application/json; charset=UTF-8", ct);
    Assert.assertEq(expected = "{\"key\": \"value\"}", body)

@Test
def testJsonMap01(): Unit \ Assert =
    let m = Map#{"name" => "Alice"};
    let r = Flame.jsonMap(m);
    let Flame.Response.Response(ct, body) = r;
    Assert.assertEq(expected = "application/json; charset=UTF-8", ct);
    Assert.assertEq(expected = "{\"name\": \"Alice\"}", body)

// App construction tests
@Test
def testApp01(): Unit \ Assert =
    let a = Flame.app();
    Assert.assertEq(expected = 8080, Flame.getPort(a));
    Assert.assertTrue(List.isEmpty(Flame.getRoutes(a)))

@Test
def testGet01(): Unit \ Assert =
    let a = Flame.app() |> Flame.get("/", _ -> Flame.text("Hello"));
    Assert.assertEq(expected = 1, List.length(Flame.getRoutes(a)))

@Test
def testPost01(): Unit \ Assert =
    let a = Flame.app() |> Flame.post("/echo", body -> Flame.text(body));
    Assert.assertEq(expected = 1, List.length(Flame.getRoutes(a)))

// Context tests
@Test
def testContext01(): Unit \ Assert =
    let ctx = Flame.context("GET", "/test", 1000i64);
    Assert.assertEq(expected = "GET", Flame.getCtxMethod(ctx));
    Assert.assertEq(expected = "/test", Flame.getCtxPath(ctx));
    Assert.assertEq(expected = 1000i64, Flame.getCtxStartTime(ctx))

// useLogger tests
@Test
def testUseLogger01(): Unit \ Assert =
    let a = Flame.app() |> Flame.useLogger;
    Assert.assertTrue(Flame.hasLogger(a))

@Test
def testUseLogger02(): Unit \ Assert =
    let a = Flame.app();
    Assert.assertFalse(Flame.hasLogger(a))

// findRoute tests
@Test
def testFindRouteGet01(): Unit \ Assert =
    let routes = Flame.Route.Get("/", _ -> Flame.text("Hello")) :: Nil;
    match Flame.findRoute("GET", "/", routes) {
        case Flame.RouteMatch.MatchedGet(_) => Assert.assertTrue(true)
        case _ => Assert.assertTrue(false)
    }

@Test
def testFindRouteGet02(): Unit \ Assert =
    let routes = Flame.Route.Get("/", _ -> Flame.text("Hello")) :: Flame.Route.Get("/ping", _ -> Flame.text("pong")) :: Nil;
    match Flame.findRoute("GET", "/ping", routes) {
        case Flame.RouteMatch.MatchedGet(h) =>
            let Flame.Response.Response(_, body) = h();
            Assert.assertEq(expected = "pong", body)
        case _ => Assert.assertTrue(false)
    }

@Test
def testFindRouteNotFound01(): Unit \ Assert =
    let routes = Flame.Route.Get("/", _ -> Flame.text("Hello")) :: Nil;
    match Flame.findRoute("GET", "/unknown", routes) {
        case Flame.RouteMatch.NotFound => Assert.assertTrue(true)
        case _ => Assert.assertTrue(false)
    }

@Test
def testFindRouteNotFound02(): Unit \ Assert =
    match Flame.findRoute("GET", "/", Nil) {
        case Flame.RouteMatch.NotFound => Assert.assertTrue(true)
        case _ => Assert.assertTrue(false)
    }

@Test
def testFindRoutePost01(): Unit \ Assert =
    let routes = Flame.Route.Post("/echo", body -> Flame.text(body)) :: Nil;
    match Flame.findRoute("POST", "/echo", routes) {
        case Flame.RouteMatch.MatchedPost(h) =>
            let Flame.Response.Response(_, body) = h("test");
            Assert.assertEq(expected = "test", body)
        case _ => Assert.assertTrue(false)
    }

@Test
def testFindRouteMethodMismatch01(): Unit \ Assert =
    let routes = Flame.Route.Get("/", _ -> Flame.text("Hello")) :: Nil;
    match Flame.findRoute("POST", "/", routes) {
        case Flame.RouteMatch.NotFound => Assert.assertTrue(true)
        case _ => Assert.assertTrue(false)
    }

// GetParam route tests
@Test
def testGetParamRoute01(): Unit \ Assert =
    let routes = Flame.Route.GetParam("/users/:id", params ->
        Flame.jsonMap(Map#{"id" => Map.getWithDefault("id", "unknown", params)})) :: Nil;
    match Flame.findRoute("GET", "/users/123", routes) {
        case Flame.RouteMatch.MatchedGetParam(h, params) =>
            let Flame.Response.Response(_, body) = h(params);
            Assert.assertTrue(String.contains({substr = "123"}, body))
        case _ => Assert.assertTrue(false)
    }

// PostParam route tests
@Test
def testPostParamRoute01(): Unit \ Assert =
    let routes = Flame.Route.PostParam("/users/:id", (params, reqBody) ->
        Flame.text("${Map.getWithDefault("id", "", params)}: ${reqBody}")) :: Nil;
    match Flame.findRoute("POST", "/users/42", routes) {
        case Flame.RouteMatch.MatchedPostParam(h, params) =>
            let Flame.Response.Response(_, body) = h(params, "test body");
            Assert.assertEq(expected = "42: test body", body)
        case _ => Assert.assertTrue(false)
    }

// State transition tests (WithServer)
//
// NoServer state: app(), get(), post(), port(), useLogger() available
// WithServer state: above + fire() available
//
// fire() is only callable in WithServer state (enforced by types)
// Calling fire() in NoServer state causes a compile error

// Mock server (exits immediately)
def mockServerImpl(_data: Flame.AppData[{}]): Unit \ { IO, Chan, NonDet } =
    unchecked_cast(() as _ \ { IO, Chan, NonDet })

// Test: server() transitions to WithServer state
@Test
def testStateTransition01(): Unit \ Assert =
    let _a: Flame.App[Flame.WithServer, {}] =
        Flame.app()
            |> Flame.server(mockServerImpl);
    Assert.assertTrue(true)

// Test: fire() is callable in WithServer state
@Test
def testFireWithMockServer01(): Unit \ { Assert, IO, Chan, NonDet } =
    let a: Flame.App[Flame.WithServer, {}] =
        Flame.app()
            |> Flame.server(mockServerImpl);
    Flame.fire(a);
    Assert.assertTrue(true)

// Test: fire() works with routes
@Test
def testFireWithMockServer02(): Unit \ { Assert, IO, Chan, NonDet } =
    let a =
        Flame.app()
            |> Flame.get("/", _ -> Flame.text("Hello"))
            |> Flame.post("/echo", body -> Flame.text(body))
            |> Flame.server(mockServerImpl);
    Flame.fire(a);
    Assert.assertTrue(true)

// Test: fire() works with configuration
@Test
def testFireWithMockServer03(): Unit \ { Assert, IO, Chan, NonDet } =
    let a =
        Flame.app()
            |> Flame.port(3000)
            |> Flame.useLogger
            |> Flame.getParam("/users/:id", params -> Flame.jsonMap(params))
            |> Flame.server(mockServerImpl);
    Flame.fire(a);
    Assert.assertTrue(true)
