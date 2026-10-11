extends Node
## Class games: the host's screen runs the town; everyone else sends what
## they do and gets back what they can see. Messages are JSON.
## In a browser it goes over PeerJS (web/net.js) with a 5-letter class code;
## on a computer (and in tests) over the local network with ENet, where the
## code is the host's address (or empty for this computer).

signal opened(id: String)
signal peer_joined(peer: String)
signal peer_left(peer: String)
signal message(peer: String, data: Dictionary)
signal failed(why: String)

const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O or 1/I mix-ups
const PORT := 47320

var active := false
var is_host := false
var enet: ENetMultiplayerPeer


func web() -> bool:
	if not OS.has_feature("web"):
		return false
	var v = JavaScriptBridge.eval("(window.ap && ap.ready()) ? 1 : 0", true)
	return v != null and int(v) == 1


static func new_code() -> String:
	var c := ""
	for i in 5:
		c += CODE_CHARS[randi() % CODE_CHARS.length()]
	return c


func host(code: String) -> void:
	active = true
	is_host = true
	if web():
		JavaScriptBridge.eval("ap.host(%s)" % JSON.stringify(code))
		return
	enet = ENetMultiplayerPeer.new()
	var err := enet.create_server(PORT, 40)
	if err != OK:
		failed.emit("couldn't open port %d" % PORT)
		return
	_enet_hooks()
	opened.emit(code)


func join(code: String) -> void:
	active = true
	is_host = false
	if web():
		JavaScriptBridge.eval("ap.join(%s)" % JSON.stringify(code.strip_edges().to_upper()))
		return
	enet = ENetMultiplayerPeer.new()
	var addr := code if code.contains(".") or code == "localhost" else "127.0.0.1"
	if enet.create_client(addr, PORT) != OK:
		failed.emit("couldn't reach %s" % addr)
		return
	opened.emit("me")


func send(peer: String, data: Dictionary) -> void:
	var s := JSON.stringify(data)
	if enet:
		enet.set_target_peer(int(peer))
		enet.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
		enet.put_packet(s.to_utf8_buffer())
	elif active:
		JavaScriptBridge.eval("ap.send(%s, %s)" % [JSON.stringify(peer), JSON.stringify(s)])


func broadcast(data: Dictionary) -> void:
	var s := JSON.stringify(data)
	if enet:
		enet.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
		enet.put_packet(s.to_utf8_buffer())
	elif active:
		JavaScriptBridge.eval("ap.broadcast(%s)" % JSON.stringify(s))


func close() -> void:
	if enet:
		enet.close()
		enet = null
	elif active:
		JavaScriptBridge.eval("ap.close()")
	active = false


func _process(_delta: float) -> void:
	if not active:
		return
	if enet:
		_poll_enet()
		return
	var raw = JavaScriptBridge.eval("ap.poll()")
	if typeof(raw) != TYPE_STRING or raw == "[]":
		return
	for e in JSON.parse_string(raw):
		match e.t:
			"open":
				opened.emit(e.id)
			"conn":
				peer_joined.emit(e.peer)
			"close":
				peer_left.emit(e.peer)
			"error":
				failed.emit(e.msg)
			"data":
				var d = JSON.parse_string(e.msg)
				if d is Dictionary:
					message.emit(e.peer, d)


var _was_connected := false


func _poll_enet() -> void:
	enet.poll()
	if not is_host:
		var st := enet.get_connection_status()
		if st == MultiplayerPeer.CONNECTION_CONNECTED and not _was_connected:
			_was_connected = true
			peer_joined.emit("1")  # the host
		elif st == MultiplayerPeer.CONNECTION_DISCONNECTED and _was_connected:
			_was_connected = false
			peer_left.emit("1")
	while enet and enet.get_available_packet_count() > 0:
		var from := enet.get_packet_peer()
		var d = JSON.parse_string(enet.get_packet().get_string_from_utf8())
		if d is Dictionary:
			message.emit(str(from), d)


func _ready() -> void:
	# (host) ENet tells us who comes and goes through these
	set_process(true)


func _enet_hooks() -> void:
	if enet and is_host and not enet.peer_connected.is_connected(_on_conn):
		enet.peer_connected.connect(_on_conn)
		enet.peer_disconnected.connect(_on_disc)


func _on_conn(id: int) -> void:
	peer_joined.emit(str(id))


func _on_disc(id: int) -> void:
	peer_left.emit(str(id))
