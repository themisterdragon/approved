// Class games: PeerJS (free public matchmaking + relay) carries
// messages between browsers. The PeerJS library is bundled (peerjs.min.js,
// MIT), so nothing outside this site is contacted until a game is hosted or
// joined. See PRIVACY.md. Godot polls ap.poll() each frame; no names or
// accounts, only a random class code.
window.ap = (() => {
  const PREFIX = "approved-classroom-";
  let peer = null, conns = {}, events = [];
  const push = (e) => events.push(e);
  function wire(c) {
    c.on("open", () => { conns[c.peer] = c; push({ t: "conn", peer: c.peer }); });
    c.on("data", (d) => push({ t: "data", peer: c.peer, msg: d }));
    c.on("close", () => { delete conns[c.peer]; push({ t: "close", peer: c.peer }); });
    c.on("error", (e) => push({ t: "error", msg: String(e) }));
  }
  function make(id) {
    peer = id ? new Peer(PREFIX + id) : new Peer();
    peer.on("error", (e) => push({ t: "error", msg: e.type || String(e) }));
    peer.on("disconnected", () => push({ t: "error", msg: "disconnected" }));
  }
  return {
    ready: () => typeof Peer !== "undefined",
    code: "",
    host(code) {
      this.code = code;  // (tests read it here)
      make(code);
      peer.on("open", () => push({ t: "open", id: code }));
      peer.on("connection", wire);
    },
    join(code) {
      make(null);
      peer.on("open", () => {
        push({ t: "open", id: peer.id });
        wire(peer.connect(PREFIX + code, { reliable: true }));
      });
    },
    send(to, msg) { const c = conns[to]; if (c && c.open) c.send(msg); },
    broadcast(msg) { for (const k in conns) if (conns[k].open) conns[k].send(msg); },
    poll() { const e = JSON.stringify(events); events = []; return e; },
    close() { if (peer) peer.destroy(); peer = null; conns = {}; },
  };
})();
