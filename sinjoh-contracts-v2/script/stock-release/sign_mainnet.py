#!/usr/bin/env python3
"""Native-terminal signing only. Password stays in memory and inherited anonymous pipes.
Deployment is already authorized; the local keystore unlock supplies signing capability.
A durable attempt marker prevents an ambiguous broadcast from being blindly repeated.
"""
import getpass, hashlib, json, os, pathlib, re, subprocess, sys, time, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[2]
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
MAX_COST = 30_000_000_000_000_000  # 0.03 ETH including 0.01 ETH infrastructure seed.
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
    inherited = ()
    if password is not None:
        read_fd, write_fd = os.pipe(); os.write(write_fd, password.encode() + b'\n'); os.close(write_fd)
        args += ['--keystore', str(KEYSTORE), '--password-file', '/dev/fd/' + str(read_fd)]
        inherited = (read_fd,)
    try:
        process = subprocess.Popen([str(a) for a in args], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, pass_fds=inherited)
        output = []
        for line in process.stdout:
            clean = safe(line); output.append(clean)
            if stream and ' WARN ' not in clean: print(clean, end='', flush=True)
        if process.wait() != 0: raise RuntimeError('Command failed. ' + ''.join(output)[-1800:])
        return ''.join(output)
    finally:
        if inherited: os.close(inherited[0])

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
def send(data, to, password, remaining):
    gas = (int(rpc('eth_estimateGas',[{'from':DEPLOYER,'to':to,'data':data}]),16) * 125 + 99) // 100
    price = fee()
    if gas * price > remaining or int(rpc('eth_getBalance',[DEPLOYER,'latest']),16) < gas * price: raise RuntimeError('Release gas budget is insufficient.')
    output = command([CAST,'send',to,'--data',data,'--gas-limit',str(gas),'--gas-price',str(price),'--json'],password)
    receipt = json.loads(output)
    return verify_receipt(receipt['transactionHash'])

def main():
    if ATTEMPT.exists(): raise RuntimeError('A mainnet attempt already exists. Reconcile its receipts before resuming; this runner will not repeat it.')
    for endpoint in [primary,secondary]:
        if int(rpc('eth_chainId',[],endpoint),16) != 4663: raise RuntimeError('Wrong signing chain.')
    verify_pin()
    print('Piggy Banks Stock sleeve · Robinhood mainnet\nSame collection and NFT. Deploy infrastructure and queue its existing 24-hour timelock.\nMaximum combined deployment/activation budget: 0.03 ETH, including the 0.01 ETH pool seed.\nActivation also waits for the local production-readiness record.\nNo NFT-owner rebalance will be signed by this key.\n', flush=True)
    status('awaiting-local-keystore-unlock', deployer=DEPLOYER, keystore=KEYSTORE.name)
    password = getpass.getpass('Deployer keystore password (local only): ')
    address = command([CAST,'wallet','address'],password).strip()
    if address.lower() != DEPLOYER.lower(): raise RuntimeError('This keystore is not the reviewed deployer: ' + address)
    if rpc('eth_getTransactionCount',[DEPLOYER,'latest']) != rpc('eth_getTransactionCount',[DEPLOYER,'pending']): raise RuntimeError('The deployer already has pending transactions.')
    status('checking-mainnet-deployment')
    command([FORGE,'script','script/PreparePiggyBanksStock.s.sol:PreparePiggyBanksStock','--rpc-url','stock_primary'],stream=True)
    pin = verify_pin()
    preparation = json.loads(PREPARATION.read_text())
    gas_price = fee()
    if 10**16 + 60_000_000 * gas_price > MAX_COST: raise RuntimeError('Deployment estimate exceeds the 0.03 ETH release budget.')
    if int(rpc('eth_getBalance',[DEPLOYER,'latest']),16) < MAX_COST: raise RuntimeError('Deployer balance is below the release reserve.')
    ATTEMPT.write_text(json.dumps({'startedAt':time.time(),'manifestHash':preparation['manifestHash'],'sourcePin':pin['scriptBytecodeSha256']},indent=2)+'\n')
    status('broadcasting-mainnet-infrastructure', manifestHash=preparation['manifestHash'])
    command([FORGE,'script','script/PreparePiggyBanksStock.s.sol:PreparePiggyBanksStock','--rpc-url','stock_primary','--broadcast','--sender',DEPLOYER,'--with-gas-price',str(gas_price)],password,True)
    preparation = json.loads(PREPARATION.read_text())
    broadcast = json.loads((ROOT/'broadcast/mainnet-stock-release/PreparePiggyBanksStock.s.sol/4663/run-latest.json').read_text())
    hashes = [r['transactionHash'] for r in broadcast['receipts']]
    receipts = [verify_receipt(h) for h in hashes]
    spent = 10**16 + sum(int(r['gasUsed'],16) * int(r['effectiveGasPrice'],16) for r in receipts)
    schedule = send(preparation['scheduleCalldata'], preparation['governance'], password, MAX_COST-spent)
    spent += int(schedule['gasUsed'],16) * int(schedule['effectiveGasPrice'],16)
    topic = command([CAST,'keccak','CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)']).strip()
    events = [log for log in schedule['logs'] if log['address'].lower()==preparation['governance'].lower() and log['topics'][0].lower()==topic.lower()]
    if not events: raise RuntimeError('Timelock scheduling event is missing.')
    operation = events[0]['topics'][1]
    ready_at = integer_call(preparation['governance'],'getTimestamp(bytes32)',operation)
    common = {'manifestHash':preparation['manifestHash'],'deploymentTransactions':hashes,'scheduleTransaction':schedule['transactionHash'],'operationId':operation,'readyAt':ready_at,'spentWei':str(spent)}
    status('queued-for-existing-timelock', **common)
    print('Scheduled. Earliest activation:',time.strftime('%Y-%m-%d %H:%M:%S UTC',time.gmtime(ready_at)),flush=True)
    print('Leave this Terminal open. It will activate only after the delay and production-readiness record both pass.',flush=True)
    while True:
        now = int(rpc('eth_getBlockByNumber',['latest',False])['timestamp'],16)
        ready = json.loads(READY.read_text()) if READY.exists() else {}
        if now >= ready_at and ready.get('manifestHash') == preparation['manifestHash'] and ready.get('scriptBytecodeSha256') == pin['scriptBytecodeSha256']: break
        time.sleep(30)
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
    print('No automatic retry will be attempted.',flush=True)
    sys.exit(1)
