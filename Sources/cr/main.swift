import ControlRoomCore
import Foundation

let usage = """
Control Room

  cr serve                         start the local server (leave it running)
  cr add "title" --tool cursor     add a ticket that's waiting on you
       [--thread name] [--link url] [--message text] [--working]
  cr list                          what's waiting, working and done
  cr later <id>                    hide it for 30 minutes
  cr park <id>                     hide it until End of day
  cr done <id>
  cr running <id>                  it's still running (moves to Working)
  cr waiting <id>                  it needs you again
  cr blocked <id>
  cr drop <id>                     delete it

  cr install-cursor-hooks          send Cursor's agents to Control Room automatically
  cr remove-cursor-hooks           stop sending them

  Tools: claude-code, claude-ai, cursor, grok, devin
  An id can be the first few letters shown by cr list.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

// MARK: Server

func serve(config: Config) -> Never {
    let store: TicketStore
    do { store = try TicketStore() } catch { fail("Couldn't read tickets.json: \(error.localizedDescription)") }
    EventQueue.drain(into: store)
    let api = API(store: store, token: config.token)
    let server: HTTPServer
    do { server = try HTTPServer(port: config.port) { api.handle($0) } } catch { fail("Couldn't start: \(error)") }
    server.start { error in
        if let error { fail("Couldn't start on port \(config.port): \(error). Is another one already running?") }
        print("Control Room server running on 127.0.0.1:\(config.port). Press Ctrl+C to stop.")
        fflush(stdout)
    }
    // Later tickets come back and done tickets expire even when nobody is asking.
    let timer = DispatchSource.makeTimerSource(queue: .global())
    timer.schedule(deadline: .now() + 30, repeating: 30)
    timer.setEventHandler {
        EventQueue.drain(into: store)
        try? store.tick()
    }
    timer.resume()
    // Release builds free locals after their last use; keep these alive for the life of the process.
    withExtendedLifetime((server, timer)) { dispatchMain() }
}

// MARK: Client

func call(_ method: String, _ path: String, body: Data? = nil, config: Config) -> Data {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(config.port)\(path)")!)
    request.httpMethod = method
    request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
    request.httpBody = body
    var result: (Data?, URLResponse?, Error?)
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { result = ($0, $1, $2); done.signal() }.resume()
    done.wait()
    if result.2 != nil { fail("The server isn't running. Start it with: cr serve") }
    let data = result.0 ?? Data()
    if let status = (result.1 as? HTTPURLResponse)?.statusCode, status >= 300 {
        let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Something went wrong (\(status))."
        fail(message)
    }
    return data
}

func elapsed(_ since: Date, _ now: Date) -> String {
    let minutes = max(0, Int(now.timeIntervalSince(since) / 60))
    return minutes < 60 ? "\(minutes) min" : "\(minutes / 60)h \(minutes % 60)m"
}

/// 24-hour clock, as in the designs ("14:27").
let clock: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm"
    return f
}()

func line(_ t: Ticket, _ now: Date) -> String {
    let where_ = t.thread.isEmpty ? t.tool.displayName : "\(t.tool.displayName) · \(t.thread)"
    let colour = t.signal(at: now).rawValue.uppercased().padding(toLength: 6, withPad: " ", startingAt: 0)
    let time = elapsed(t.stateSince, now).padding(toLength: 8, withPad: " ", startingAt: 0)
    var out = "  \(t.shortID)  \(colour) \(time) [\(t.tool.initial)] \(where_) — \(t.title)"
    if t.state == .later, let until = t.laterUntil { out += "  (back at \(clock.string(from: until)))" }
    if t.laterCount > 0 { out += "  · Later ×\(t.laterCount)" }
    return out
}

func list(config: Config) {
    let tickets = (try? JSONDecoder.controlRoom.decode([Ticket].self, from: call("GET", "/tickets", config: config))) ?? []
    let now = Date()
    let groups: [(String, [TicketState])] = [
        ("WAITING ON YOU", [.needsYou, .blocked]),
        ("WORKING", [.working]),
        ("DONE TODAY", [.done]),
        ("LATER AND PARKED", [.later, .parked]),
    ]
    if tickets.isEmpty { print("No tickets. Add one with: cr add \"title\" --tool cursor"); return }
    for (heading, states) in groups {
        // Oldest first, as in the notch panel.
        let rows = tickets.filter { states.contains($0.state) }.sorted { $0.stateSince < $1.stateSince }
        guard !rows.isEmpty else { continue }
        print("\(heading)  \(rows.count)")
        rows.forEach { print(line($0, now)) }
        print("")
    }
}

func add(_ args: [String], config: Config) {
    var title: String?
    var options: [String: String] = [:]
    var working = false
    var i = 0
    while i < args.count {
        let arg = args[i]
        if arg == "--working" { working = true }
        else if arg.hasPrefix("--") {
            guard i + 1 < args.count else { fail("\(arg) needs a value.") }
            options[String(arg.dropFirst(2))] = args[i + 1]
            i += 1
        } else if title == nil { title = arg }
        else { fail("Put the title in quotes: cr add \"\(args.joined(separator: " "))\" ...") }
        i += 1
    }
    guard let title else { fail("Give it a title: cr add \"title\" --tool cursor") }
    guard let toolName = options["tool"] else { fail("Say which tool: --tool claude-code, claude-ai, cursor, grok or devin") }
    guard let tool = Tool(rawValue: toolName) else { fail("Unknown tool \(toolName). Use claude-code, claude-ai, cursor, grok or devin.") }
    let new = API.NewTicket(tool: tool, title: title, thread: options["thread"], lastMessage: options["message"],
                            deepLink: options["link"], state: working ? .working : .needsYou)
    let data = call("POST", "/tickets", body: try? JSONEncoder.controlRoom.encode(new), config: config)
    if let t = try? JSONDecoder.controlRoom.decode(Ticket.self, from: data) {
        print("Added \(t.shortID): \(t.title) (\(t.state == .working ? "working" : "waiting on you"))")
    }
}

func move(_ path: String, _ id: String?, verb: String, config: Config) {
    guard let id else { fail("Which ticket? Give the id from cr list.") }
    let data = call("POST", "/tickets/\(id)/\(path)", config: config)
    if let t = try? JSONDecoder.controlRoom.decode(Ticket.self, from: data) { print("\(verb): \(t.title)") }
}

// MARK: Main

let args = Array(CommandLine.arguments.dropFirst())
let config: Config
do { config = try Config.loadOrCreate() } catch { fail("Couldn't read settings: \(error.localizedDescription)") }

switch args.first {
case "serve": serve(config: config)
case "add": add(Array(args.dropFirst()), config: config)
case "list", nil: list(config: config)
case "later": move("later", args.dropFirst().first, verb: "Later", config: config)
case "park": move("park", args.dropFirst().first, verb: "Parked", config: config)
case "done": move("done", args.dropFirst().first, verb: "Done", config: config)
case "running": move("still-running", args.dropFirst().first, verb: "Working", config: config)
case "waiting": move("needs-you", args.dropFirst().first, verb: "Waiting on you", config: config)
case "blocked": move("blocked", args.dropFirst().first, verb: "Blocked", config: config)
case "drop": move("drop", args.dropFirst().first, verb: "Dropped", config: config)
case "install-cursor-hooks":
    do {
        try CursorHooks.install()
        print("Cursor's agents will now show up in Control Room. Cursor picks this up straight away; no restart needed.")
    } catch { fail("Couldn't install: \(error.localizedDescription)") }
case "remove-cursor-hooks":
    do {
        try CursorHooks.remove()
        print("Removed. Cursor's agents won't be sent to Control Room any more.")
    } catch { fail("Couldn't remove: \(error.localizedDescription)") }
case "help", "-h", "--help": print(usage)
default: print(usage); exit(1)
}
