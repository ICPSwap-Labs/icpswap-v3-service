import json
import os
from pathlib import Path
import subprocess
import urllib.request
from collections import Counter

DFX = os.environ.get("DFX", "dfx")


def command(*args):
    result = subprocess.run([DFX, *args], text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout.strip()


principal = command("identity", "get-principal")
command("canister", "create", "--all", "--no-wallet")
token_a = command("canister", "id", "token_a")
token_b = command("canister", "id", "token_b")
for token in ("token_a", "token_b"):
    command("canister", "install", token, "--wasm", "MockLedger.wasm", "--argument", "()")
pool_args = (
    f'(record {{ address = "{token_a}"; standard = "ICRC2" }}, '
    f'record {{ address = "{token_b}"; standard = "ICRC2" }}, '
    f'principal "{principal}", principal "{principal}", principal "{principal}")'
)
command("canister", "install", "pool", "--wasm", "SwapPool.wasm", "--argument", pool_args)
port = Path(".dfx/network/local/pocket-ic-port").read_text().strip()
pic = f"http://127.0.0.1:{port}/instances/0/"


def call(canister, method, arg="()", query=False):
    args = ["canister", "call", canister, method, arg,
            "--output", "json", "--impersonate", principal]
    if query:
        args.append("--query")
    output = command(*args)
    return json.loads(output) if output else None


def api(path, body=None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(pic + path, data=data,
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def queue():
    return call("pool", "getWithdrawQueueInfo", query=True)["ok"]


def inflight():
    return call("pool", "getInFlightWithdrawals", query=True)["ok"]


call("pool", "init", "(3000, 60, 79228162514264337593543950336)")
call("token_a", "setDelay", "(80)")
call("pool", "depositFrom", f'(record {{ token = "{token_a}"; amount = 1000; fee = 1 }})')
call("pool", "withdraw", f'(record {{ token = "{token_a}"; amount = 400; fee = 1 }})')
first = inflight()
assert len(first) == 1, first
first_id = first[0]["item"]["txIndex"]
assert first[0]["item"]["amount"] == "400", first
call("pool", "withdraw", f'(record {{ token = "{token_a}"; amount = 300; fee = 1 }})')
before = queue()
assert before["queueSize"] == "1", before
second_id = before["items"][0]["txIndex"]
assert second_id != first_id
call("token_a", "setDelay", "(0)")

api("stop_progress", "")
now = api("read/get_time")["nanos_since_epoch"]
api("update/set_time", {"nanos_since_epoch": now + 601_000_000_000})
for _ in range(20):
    api("update/tick", {})

after_watchdog = queue()
unresolved = inflight()
paid_after_watchdog = call("token_a", "getTransfers", query=True)
assert after_watchdog["queueSize"] == "0", after_watchdog
assert not after_watchdog["isProcessing"], after_watchdog
assert [entry["item"]["txIndex"] for entry in unresolved] == [first_id], unresolved
assert len(paid_after_watchdog) == 1, paid_after_watchdog
assert paid_after_watchdog[0]["amount"] == "299", paid_after_watchdog

for _ in range(250):
    api("update/tick", {})

final_queue = queue()
final_inflight = inflight()
paid = call("token_a", "getTransfers", query=True)
assert final_inflight == [], final_inflight
assert final_queue["queueSize"] == "0" and not final_queue["isProcessing"], final_queue
assert Counter(entry["amount"] for entry in paid) == Counter({"299": 1, "399": 1}), paid
assert len({json.dumps(entry["memo"]) for entry in paid}) == 2, paid
print(json.dumps({
    "watchdog_recovery": "PASS",
    "delayed_tx": first_id,
    "later_tx": second_id,
    "later_payment_before_delayed_reply": True,
    "payments_per_memo": "exactly one",
    "delayed_reply_clears_remaining_record": True,
    "final_queue_empty": True,
    "final_inflight_empty": True,
}, indent=2))
