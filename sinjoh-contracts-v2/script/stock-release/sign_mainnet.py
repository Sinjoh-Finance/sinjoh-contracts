#!/usr/bin/env python3
"""Native-terminal signing only. Password stays in memory and an echo-disabled local terminal.
Deployment is already authorized; the local keystore unlock supplies signing capability.
A durable attempt marker prevents an ambiguous broadcast from being blindly repeated.
"""
import getpass, hashlib, json, os, pathlib, re, subprocess, sys, time, urllib.request
from keystore_terminal import run_keystore_command
ROOT = pathlib.Path(__file__).resolve().parents[2]
RAW_SIGNING = '--interactive-key' in sys.argv
RESUME = '--resume-activation' in sys.argv
FORGE = pathlib.Path.home() / '.foundry/bin/forge'
CAST = pathlib.Path.home() / '.foundry/bin/cast'
DEPLOYER = '0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49'
KEYSTORE = pathlib.Path.home() / '.foundry/keystores/sinjoh-v2-mainnet-deployer'
STATUS = ROOT / 'deployments/stock-signing-status.json'
ATTEMPT = ROOT / 'deployments/stock-mainnet-attempt.json'
PIN = ROOT / 'deployments/stock-source-pin.json'
READY = ROOT / 'deployments/stock-production-ready.json'
PREPARATION = ROOT / 'deployments/piggy-banks-stock-preparation.json'
ARTIFACT = ROOT / 'out/PreparePiggyBanksStock.s.sol/PreparePiggyBanksStock.json'
MAX_COST = 30_000_000_000_000_000  # Includes deployment, activation, pool seed and worker gas.
WORKER = '0x2456209DA46B127ff2c732cb2F5f0378caA9587e'
WORKER_GAS_TARGET = 10_000_000_000_000_000  # Dedicated operational gas only.
config = json.loads(pathlib.Path('/tmp/sinjoh-stock-rpc.json').read_text())
primary, secondary = config['SINJOH_RPC_PRIMARY'], config['SINJOH_RPC_SECONDARY']
env = os.environ.copy()
env.update(ETH_RPC_URL=primary, SINJOH_STOCK_RPC_PRIMARY=primary, SINJOH_STOCK_RPC_VERIFICATION=secondary,
           FOUNDRY_BROADCAST=str(ROOT / 'broadcast/mainnet-stock-release'))
for name in ['ETH_PRIVATE_KEY', 'PRIVATE_KEY', 'ETH_KEYSTORE', 'ETH_PASSWORD', 'ETH_PASSWORD_FILE']:
    env.pop(name, None)
def safe(value):
    text = str(value)
    for secret in config.values(): text = text.replace(secret, '[RPC]')
    return text

def status(phase, **fields):
    value = {'phase': phase, 'updatedAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), **fields}
    temporary = STATUS.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n'); temporary.replace(STATUS)
    print(phase, flush=True)

def rpc(method, params, endpoint=primary):
    body = json.dumps({'jsonrpc':'2.0','id':1,'method':method,'params':params}).encode()
    req = urllib.request.Request(endpoint, body, {'Content-Type':'application/json'})
    response = json.loads(urllib.request.urlopen(req, timeout=30).read())
    if 'error' in response: raise RuntimeError('RPC request failed: ' + method)
    return response['result']

def command(args, password=None, stream=False):
    if password is not None:
        def emit(line):
            clean = safe(line)
            if stream and ' WARN ' not in clean: print(clean, end='', flush=True)
        code, output = run_keystore_command([*args, *(['--interactive'] if RAW_SIGNING else ['--keystore', str(KEYSTORE)])], password, ROOT, env, emit)
        output = safe(output)
        if code != 0: raise RuntimeError('Command failed. ' + output[-1800:])
        return output
    process = subprocess.Popen([str(a) for a in args], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    output = []
    for line in process.stdout:
        clean = safe(line); output.append(clean)
        if stream and ' WARN ' not in clean: print(clean, end='', flush=True)
    if process.wait() != 0: raise RuntimeError('Command failed. ' + ''.join(output)[-1800:])
    return ''.join(output)

def verify_pin():
    pin = json.loads(PIN.read_text())
    code = json.loads(ARTIFACT.read_text())['bytecode']['object']
    if hashlib.sha256(code.encode()).hexdigest() != pin['scriptBytecodeSha256']: raise RuntimeError('Deployment bytecode changed after review.')
    for relative, digest in pin['files'].items():
        if hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() != digest: raise RuntimeError('Release input changed: ' + relative)
    return pin

def encoded(signature, *args): return command([CAST, 'calldata', signature, *args]).strip()
def integer_call(to, signature, *args): return int(rpc('eth_call', [{'to':to, 'data':encoded(signature, *args)}, 'latest']), 16)
def fee():
    price = (int(rpc('eth_gasPrice', []),16) * 125 + 99) // 100
    if price > 1_000_000_000: raise RuntimeError('Gas exceeds the release fee ceiling.')
    return max(1, price)
def verify_receipt(hash_):
    a = rpc('eth_getTransactionReceipt', [hash_])
    if not a or int(a['status'],16) != 1: raise RuntimeError('Transaction is not confirmed successful: ' + hash_)
    for attempt in range(12):
        b = rpc('eth_getTransactionReceipt', [hash_], secondary)
        if b and b['blockHash'] == a['blockHash'] and b['status'] == a['status']: return a
        time.sleep(5)
    raise RuntimeError('Independent receipt verification is pending: ' + hash_)
def send(data, to, password, remaining, value=0):
    gas = (int(rpc('eth_estimateGas',[{'from':DEPLOYER,'to':to,'data':data,'value':hex(value)}]),16) * 125 + 99) // 100
    price = fee()
    if value + gas * price > remaining or int(rpc('eth_getBalance',[DEPLOYER,'latest']),16) < value + gas * price: raise RuntimeError('Release gas budget is insufficient.')
    nonce = rpc('eth_getTransactionCount',[DEPLOYER,'latest'])
    if nonce != rpc('eth_getTransactionCount',[DEPLOYER,'pending']): raise RuntimeError('Reconcile the pending signer transaction first.')
    # Sign locally, then durably record the public signed transaction before RPC submission.
    # This avoids parsing terminal log output as a receipt and permits exact-hash recovery.
    output = command([CAST,'mktx',to,data,'--gas-limit',str(gas),'--gas-price',str(price),'--priority-gas-price','0','--nonce',str(int(nonce,16)),'--chain','4663','--value',str(value),'--color','never'],password)
    candidates = re.findall(r'^0x[0-9a-fA-F]{100,}$', output, re.M)
    if len(candidates) != 1: raise RuntimeError('Signed transaction output is invalid; nothing was submitted.')
    raw = candidates[0]
    hash_ = command([CAST,'keccak',raw]).strip()
    record = {'transactionHash':hash_,'signedTransaction':raw,'to':to,'valueWei':str(value),'nonce':int(nonce,16),'data':data,'at':time.time()}
    fd = os.open(ROOT/'deployments/stock-signed-submissions.jsonl', os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd,'a') as journal:
        journal.write(json.dumps(record)+'\n');journal.flush();os.fsync(journal.fileno())
    submitted = rpc('eth_sendRawTransaction',[raw])
    if submitted.lower() != hash_.lower(): raise RuntimeError('Submission hash mismatch; reconcile the signed journal.')
    for _ in range(120):
        if rpc('eth_getTransactionReceipt',[hash_]): return verify_receipt(hash_)
        time.sleep(1)
    raise RuntimeError('Receipt pending; reconcile '+hash_)

def wait_for_activation(preparation, pin, ready_at, common):
    """Retry read-only waiting after network outages, never a signing/submission action.

    Both independent providers must report the correct chain and a mature block time.
    The existing submission path remains single-attempt and journaled before broadcast.
    """
    degraded = False
    while True:
        timestamps = []
        for endpoint in (primary, secondary):
            try:
                chain = int(rpc('eth_chainId', [], endpoint), 16)
                timestamp = int(rpc('eth_getBlockByNumber', ['latest', False], endpoint)['timestamp'], 16)
            except (OSError, TimeoutError, RuntimeError):
                # Do not log endpoint strings or change the preserved schedule evidence.
                continue
            if chain != 4663:
                raise RuntimeError('Wrong chain while waiting for Stock activation.')
            timestamps.append(timestamp)
        if len(timestamps) != 2:
            if not degraded:
                status('waiting-for-rpc-recovery', **common)
                degraded = True
        else:
            if degraded:
                status('queued-for-existing-timelock', **common)
                degraded = False
            ready = json.loads(READY.read_text()) if READY.exists() else {}
            if (min(timestamps) >= ready_at
                    and ready.get('manifestHash') == preparation['manifestHash']
                    and ready.get('scriptBytecodeSha256') == pin['scriptBytecodeSha256']):
                return
        time.sleep(30)

def main():
    if ATTEMPT.exists() and not RESUME: raise RuntimeError('A mainnet attempt already exists. Reconcile its receipts before resuming; this runner will not repeat it.')
    if RESUME and not ATTEMPT.exists(): raise RuntimeError('There is no deployment attempt to reconcile.')
    for endpoint in [primary,secondary]:
        if int(rpc('eth_chainId',[],endpoint),16) != 4663: raise RuntimeError('Wrong signing chain.')
    verify_pin()
    print('Piggy Banks Stock sleeve · Robinhood mainnet\nSame collection and NFT. Deploy infrastructure and queue its existing 24-hour timelock.\nMaximum combined deployment/activation budget: 0.03 ETH, including the 0.01 ETH pool seed and up to 0.01 ETH for the dedicated dividend worker.\nActivation also waits for the local production-readiness record.\nNo NFT-owner rebalance will be signed by this key.\n', flush=True)
    status('awaiting-local-signer-input' if RAW_SIGNING else 'awaiting-local-keystore-unlock', deployer=DEPLOYER)
    password = getpass.getpass('Local signer input: ' if RAW_SIGNING else 'Deployer keystore password (local only): ')
    if RAW_SIGNING and not re.fullmatch(r'0x[0-9a-fA-F]{64}', password): raise RuntimeError('Invalid signer input format.')
    if ATTEMPT.exists() and not RESUME: raise RuntimeError('Another deployment attempt started; reconcile before proceeding.')
    address = command([CAST,'wallet','address'],password).strip()
    if address.lower() != DEPLOYER.lower(): raise RuntimeError('The signer does not match the reviewed deployer: ' + address)
    if rpc('eth_getTransactionCount',[DEPLOYER,'latest']) != rpc('eth_getTransactionCount',[DEPLOYER,'pending']): raise RuntimeError('The deployer already has pending transactions.')
    if not RESUME:
        status('checking-mainnet-deployment')
        command([FORGE,'script','script/PreparePiggyBanksStock.s.sol:PreparePiggyBanksStock','--rpc-url','stock_primary'],stream=True)
        pin = verify_pin()
        preparation = json.loads(PREPARATION.read_text())
        gas_price = fee()
        worker_funding = max(0, WORKER_GAS_TARGET - int(rpc('eth_getBalance',[WORKER,'latest']),16))
        if 10**16 + worker_funding + 60_000_000 * gas_price > MAX_COST: raise RuntimeError('Deployment estimate exceeds the 0.03 ETH release budget.')
        if int(rpc('eth_getBalance',[DEPLOYER,'latest']),16) < MAX_COST: raise RuntimeError('Deployer balance is below the release reserve.')
        ATTEMPT.write_text(json.dumps({'startedAt':time.time(),'manifestHash':preparation['manifestHash'],'sourcePin':pin['scriptBytecodeSha256']},indent=2)+'\n')
        status('broadcasting-mainnet-infrastructure', manifestHash=preparation['manifestHash'])
        command([FORGE,'script','script/PreparePiggyBanksStock.s.sol:PreparePiggyBanksStock','--rpc-url','stock_primary','--broadcast','--sender',DEPLOYER,'--with-gas-price',str(gas_price)],password,True)
    pin = verify_pin()
    preparation = json.loads(PREPARATION.read_text())
    broadcast = json.loads((ROOT/'broadcast/mainnet-stock-release/PreparePiggyBanksStock.s.sol/4663/run-latest.json').read_text())
    hashes = [r['transactionHash'] for r in broadcast['receipts']]
    receipts = [verify_receipt(h) for h in hashes]
    spent = 10**16 + sum(int(r['gasUsed'],16) * int(r['effectiveGasPrice'],16) for r in receipts)
    if RESUME:
        reconciliation = json.loads((ROOT/'deployments/stock-reconciliation.json').read_text())
        hashes_ = reconciliation['scheduleTransactions']
        if len(hashes_) != 1: raise RuntimeError('Expected exactly one reconciled schedule receipt.')
        for endpoint in [primary,secondary]:
            transaction = rpc('eth_getTransactionByHash',[hashes_[0]],endpoint)
            if not transaction or transaction['from'].lower()!=DEPLOYER.lower() or transaction['to'].lower()!=preparation['governance'].lower() or transaction['input'].lower()!=preparation['scheduleCalldata'].lower(): raise RuntimeError('Schedule transaction does not match this release.')
        schedule = verify_receipt(hashes_[0])
        # Any prior signed recovery transaction must be reconciled before another send.
        journal = ROOT/'deployments/stock-signed-submissions.jsonl'
        if journal.exists():
            for line in journal.read_text().splitlines():
                entry = json.loads(line); receipt = verify_receipt(entry['transactionHash'])
                spent += int(entry['valueWei']) + int(receipt['gasUsed'],16)*int(receipt['effectiveGasPrice'],16)
    else:
        schedule = send(preparation['scheduleCalldata'], preparation['governance'], password, MAX_COST-spent)
    spent += int(schedule['gasUsed'],16) * int(schedule['effectiveGasPrice'],16)
    topic = command([CAST,'keccak','CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)']).strip()
    events = [log for log in schedule['logs'] if log['address'].lower()==preparation['governance'].lower() and log['topics'][0].lower()==topic.lower()]
    if not events: raise RuntimeError('Timelock scheduling event is missing.')
    operation = events[0]['topics'][1]
    ready_at = integer_call(preparation['governance'],'getTimestamp(bytes32)',operation)
    common = {'manifestHash':preparation['manifestHash'],'deploymentTransactions':hashes,'scheduleTransaction':schedule['transactionHash'],'operationId':operation,'readyAt':ready_at,'spentWei':str(spent)}
    worker_funding = max(0, WORKER_GAS_TARGET - int(rpc('eth_getBalance',[WORKER,'latest']),16))
    if worker_funding:
        status('funding-dedicated-dividend-worker', **common, worker=WORKER, valueWei=str(worker_funding))
        funding = send('0x', WORKER, password, MAX_COST-spent, worker_funding)
        spent += worker_funding + int(funding['gasUsed'],16) * int(funding['effectiveGasPrice'],16)
        common.update(workerFundingTransaction=funding['transactionHash'], worker=WORKER, spentWei=str(spent))
    status('queued-for-existing-timelock', **common)
    print('Scheduled. Earliest activation:',time.strftime('%Y-%m-%d %H:%M:%S UTC',time.gmtime(ready_at)),flush=True)
    print('Leave this Terminal open. It will activate only after the delay and production-readiness record both pass.',flush=True)
    wait_for_activation(preparation, pin, ready_at, common)
    verify_pin()
    controller = integer_call('0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1', 'deltaPoolController()')
    controller_address = '0x' + format(controller,'040x')
    if int(rpc('eth_getTransactionCount',[controller_address,'latest']),16) != preparation['controllerNonce']: raise RuntimeError('Controller creation nonce changed; rebuild the activation plan before spending gas.')
    status('activating-mainnet-stock-sleeve', **common)
    activation = send(preparation['executeCalldata'],preparation['governance'],password,MAX_COST-spent)
    status('mainnet-activated-awaiting-application-cutover', **common, activationTransaction=activation['transactionHash'], activationBlock=activation['blockNumber'])
    password = None

try: main()
except KeyboardInterrupt: status('signing-interrupted-reconcile-before-retry')
except Exception as error:
    status('signing-needs-attention', error=safe(error))
    print(safe(error), flush=True)
    print('No automatic retry will be attempted.',flush=True)
    sys.exit(1)
