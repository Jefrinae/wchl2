// src/emergency_canister_backend/main.mo
import Time "mo:base/Time";
import Array "mo:base/Array";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Int "mo:base/Int";

actor SOS {
  // Public type exposed to clients (aligns with Python expectations)
  public type Alert = {
    id: Text;
    reporter: Text;
    lat: Float;
    lon: Float;
    timestamp: Nat;
    message: Text;
    active: Bool;
    responder: ?Text;
  };

  // Internal type to store with Nat ids
  type Stored = {
    id: Nat;
    reporter: Text;
    lat: Float;
    lon: Float;
    timestamp: Time.Time;
    message: Text;
    active: Bool;
    responder: ?Text;
  };

  stable var items : [Stored] = [];
  stable var nextId : Nat = 0;

  // Convert internal to public
  func toAlert(x: Stored) : Alert {
    {
      id = Nat.toText(x.id);
      reporter = x.reporter;
      lat = x.lat;
      lon = x.lon;
      timestamp = Int.abs(x.timestamp);
      message = x.message;
      active = x.active;
      responder = x.responder;
    }
  };

  // add_sos(reporter, lat, lon, message) -> text (id)
  public func add_sos(reporter: Text, lat: Float, lon: Float, message: Text) : async Text {
    let id = nextId;
    nextId += 1;
    let now = Time.now();
    let st : Stored = {
      id = id;
      reporter = reporter;
      lat = lat;
      lon = lon;
      timestamp = now;
      message = message;
      active = true;
      responder = null;
    };
    items := Array.append<Stored>(items, [st]);
    return Nat.toText(id);
  };

  // list_active() -> [Alert]
  public query func list_active() : async [Alert] {
    let filtered = Array.filter<Stored>(items, func (x: Stored) : Bool { x.active });
    Array.map<Stored, Alert>(filtered, toAlert)
  };

  // resolve_sos(id, responder) -> bool
  public func resolve_sos(idText: Text, responder: Text) : async Bool {
    switch (Nat.fromText(idText)) {
      case (?idNat) {
        var changed = false;
        let n = items.size();
        let newItems = Array.tabulate<Stored>(n, func(i : Nat) : Stored {
          let it = items[i];
          if (not changed and it.id == idNat and it.active) {
            changed := true;
            {
              id = it.id;
              reporter = it.reporter;
              lat = it.lat;
              lon = it.lon;
              timestamp = it.timestamp;
              message = it.message;
              active = false;
              responder = ?responder;
            }
          } else {
            it
          }
        });
        items := newItems;
        return changed;
      };
      case null { return false; };
    };
  };

  // cancel_sos(id) -> bool
  public func cancel_sos(idText: Text) : async Bool {
    switch (Nat.fromText(idText)) {
      case (?idNat) {
        var changed = false;
        let n = items.size();
        let newItems = Array.tabulate<Stored>(n, func(i : Nat) : Stored {
          let it = items[i];
          if (not changed and it.id == idNat and it.active) {
            changed := true;
            {
              id = it.id;
              reporter = it.reporter;
              lat = it.lat;
              lon = it.lon;
              timestamp = it.timestamp;
              message = it.message;
              active = false;
              responder = it.responder;
            }
          } else {
            it
          }
        });
        items := newItems;
        return changed;
      };
      case null { return false; };
    };
  };
};
