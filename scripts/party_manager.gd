extends Node

# ============================================================
# PARTY MANAGER (server-side)
# Attached as a child of ServerMain.
# Parties: { party_id(int) -> { "leader": peer_id, "members": [peer_ids] } }
# ============================================================

var _parties:  Dictionary = {}   # party_id -> { leader, members }
var _in_party: Dictionary = {}   # peer_id  -> party_id
var _next_id:  int        = 1

func _get_sm():
	return get_parent()

# ── Public API ───────────────────────────────────────────────

func on_invite(inviter_id: int, target_name: String) -> void:
	var sm = _get_sm()
	# Resolve target peer_id by username
	var target_id = -1
	for pid in sm.server_players:
		if sm.server_players[pid].username == target_name:
			target_id = pid
			break
	if target_id == -1:
		Network.receive_party_msg.rpc_id(inviter_id, "system", "Player '%s' is not online." % target_name)
		return
	if target_id == inviter_id:
		Network.receive_party_msg.rpc_id(inviter_id, "system", "You cannot invite yourself.")
		return
	if _in_party.has(target_id):
		Network.receive_party_msg.rpc_id(inviter_id, "system", "%s is already in a party." % target_name)
		return
	var inviter_name = sm.server_players[inviter_id].username
	# Verify target is still a connected peer
	var connected_peers = multiplayer.get_peers()
	print("[PARTY] Connected peers: ", connected_peers)
	print("[PARTY] target_id=%d  inviter_id=%d  inviter_name=%s" % [target_id, inviter_id, inviter_name])
	if target_id not in connected_peers:
		Network.receive_party_msg.rpc_id(inviter_id, "system", "Player '%s' is no longer connected." % target_name)
		return
	print("[PARTY] Sending receive_party_invite RPC to peer %d" % target_id)
	Network.receive_party_invite.rpc_id(target_id, inviter_name)
	print("[PARTY] RPC dispatched")
	Network.receive_party_msg.rpc_id(inviter_id, "system", "Party invite sent to %s." % target_name)

func on_accept(accepter_id: int, inviter_name: String) -> void:
	var sm = _get_sm()
	# Resolve inviter peer_id
	var inviter_id = -1
	for pid in sm.server_players:
		if sm.server_players[pid].username == inviter_name:
			inviter_id = pid
			break
	if inviter_id == -1:
		Network.receive_party_msg.rpc_id(accepter_id, "system", "Invite expired — player disconnected.")
		return
	if _in_party.has(accepter_id):
		Network.receive_party_msg.rpc_id(accepter_id, "system", "You are already in a party.")
		return

	var party_id: int
	if _in_party.has(inviter_id):
		# Inviter already has a party — join it
		party_id = _in_party[inviter_id]
		if _parties[party_id]["members"].size() >= 4:
			Network.receive_party_msg.rpc_id(accepter_id, "system", "That party is full (max 4).")
			return
		_parties[party_id]["members"].append(accepter_id)
	else:
		# Create new party
		party_id = _next_id
		_next_id += 1
		_parties[party_id] = { "leader": inviter_id, "members": [inviter_id, accepter_id] }
		_in_party[inviter_id] = party_id

	_in_party[accepter_id] = party_id
	_broadcast_party(party_id)

func on_decline(decliner_id: int, inviter_name: String) -> void:
	var sm = _get_sm()
	var inviter_id = -1
	for pid in sm.server_players:
		if sm.server_players[pid].username == inviter_name:
			inviter_id = pid
			break
	var decliner_name = sm.server_players[decliner_id].username if sm.server_players.has(decliner_id) else "?"
	if inviter_id != -1:
		Network.receive_party_msg.rpc_id(inviter_id, "system", "%s declined your party invite." % decliner_name)

func on_leave(peer_id: int) -> void:
	if not _in_party.has(peer_id):
		return
	var party_id = _in_party[peer_id]
	_remove_from_party(peer_id, party_id)

func on_disconnect(peer_id: int) -> void:
	# Called by server_main when a player disconnects
	on_leave(peer_id)

func get_party_usernames(peer_id: int) -> Array:
	# Returns usernames of all party members including self, or empty if not in party
	if not _in_party.has(peer_id):
		return []
	var party_id = _in_party[peer_id]
	var sm = _get_sm()
	var names = []
	for pid in _parties[party_id]["members"]:
		if sm.server_players.has(pid):
			names.append(sm.server_players[pid].username)
	return names

func get_party_id(peer_id: int) -> int:
	return _in_party.get(peer_id, -1)

# ── Internal ─────────────────────────────────────────────────

func _remove_from_party(peer_id: int, party_id: int) -> void:
	var sm = _get_sm()
	var party = _parties[party_id]
	party["members"].erase(peer_id)
	_in_party.erase(peer_id)

	var leaving_name = sm.server_players[peer_id].username if sm.server_players.has(peer_id) else "?"
	Network.receive_party_msg.rpc_id(peer_id, "system", "You left the party.")

	if party["members"].is_empty():
		_parties.erase(party_id)
		return

	# Pass leadership if leader left
	if party["leader"] == peer_id:
		party["leader"] = party["members"][0]
		var new_leader_name = sm.server_players[party["leader"]].username if sm.server_players.has(party["leader"]) else "?"
		for pid in party["members"]:
			Network.receive_party_msg.rpc_id(pid, "system", "%s left. %s is now the leader." % [leaving_name, new_leader_name])
	else:
		for pid in party["members"]:
			Network.receive_party_msg.rpc_id(pid, "system", "%s left the party." % leaving_name)

	# Disband if only 1 left
	if party["members"].size() == 1:
		var last = party["members"][0]
		_in_party.erase(last)
		_parties.erase(party_id)
		Network.receive_party_msg.rpc_id(last, "system", "Party disbanded.")
		Network.receive_party_update.rpc_id(last, [])
		return

	_broadcast_party(party_id)

func _broadcast_party(party_id: int) -> void:
	var sm = _get_sm()
	var party = _parties[party_id]
	# Build username list for all members
	var names = []
	for pid in party["members"]:
		if sm.server_players.has(pid):
			names.append(sm.server_players[pid].username)
	# Send to all members
	for pid in party["members"]:
		Network.receive_party_update.rpc_id(pid, names)
