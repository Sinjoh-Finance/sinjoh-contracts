#!/bin/zsh
# Verifies every Sinjoh pools.trade contract on Blockscout. Idempotent:
# already-verified contracts are skipped by the verifier. The public
# Blockscout instance rate-limits verification submissions per IP, so on a
# partial run simply re-run this script after the limiter resets; nothing
# breaks if it is run twice. The MerkleClaimFactory (last entry) verifies
# against the upstream Uniswap/liquidity-launcher checkout at commit dd8769c,
# so set MERKLE_UPSTREAM_DIR to that checkout when verifying it.
cd /Users/dsb/Sinjoh/sinjoh-launchpad-adapters
L=0x0000FffFBE8efE702c8703aE3477FF5dE3d319C0; TF=0x000000e200088D55C39a11F609E5F667729ad49b
SCF=0x23f8209572b4a1C2AD88A42749E830791Fb027f1; SNF=0xAD44D55E7f8337C3cE113fBb591486E85be104b2
LBPS=0x05d552391067389EE44fec3924157ed33F976000; SPL=0x4F5E3FBb9745358A92Da5674305FAb8D2B8a73cE
MK=0x0C8B3e001C8DbBDbe15089c887C9323E097F0a15; W=0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73
PM=0x8366a39CC670B4001A1121B8F6A443A643e40951; V3R=0xCaf681a66D020601342297493863E78C959E5cb2
TWAP=0xfdd4f594A9f7cD17fEE0BBF2859F4eEA3265F328
LBPFAC=0x6A4D50D9469fed073c4445Dc4050cd29d1BE25D7
SCFH=0x29df27cf43533e9b3708dcd2a2c0fd17a1a8796407e7d39375f47e5c809cffca
LBPFH=0xf87731535792f63f7fe130e58a1ea057b707c2fc03b1df4092a3ff3f433e3d57
PMH=0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626
WH=0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353
V3RH=0x6f36c378e272c6324c48f045182bcb54bd8ad654cf9ebd42e8893d52c4cb25dc
SIGNER=0xd89fB916dD031Da9b0A32e820307c2d41a7dDe09
VURL="https://robinhoodchain.blockscout.com/api"
ANF=$(cast abi-encode "c(address,address,address,address,uint256)" $L $TF $SNF $W 4663)
ALBPF=$(cast abi-encode "c(address,address,address,address,address,address,uint256)" $L $TF $LBPS $SPL $MK $W 4663)
ALBPI=$(cast abi-encode "c(address,address,address,address,address,address,uint256,address)" $L $TF $LBPS $SPL $MK $W 4663 $LBPFAC)
ABB=$(cast abi-encode "c(address,address,address,address,bytes32,bytes32,bytes32,bytes32)" $SCF $LBPFAC $PM $W $SCFH $LBPFH $PMH $WH)
ABG=$(cast abi-encode "c(address,bytes32,address)" $W $WH $SIGNER)
ASELL=$(cast abi-encode "c(address,address,address,address,address,bytes32,bytes32,bytes32,bytes32,bytes32)" $SCF $LBPFAC $PM $V3R $W $SCFH $LBPFH $PMH $V3RH $WH)
ASG=$(cast abi-encode "c(address,address,address,address,address,uint16,uint48)" $SCF $LBPFAC $PM $W $TWAP 500 300)
v() { forge verify-contract "$1" "$2" --verifier blockscout --verifier-url $VURL --constructor-args "$3" 2>&1 | tail -2; sleep 90; }
v 0xD99F640b3dac6032471F5D7e509c54232BAc397d src/SinjohPoolsTradeInstantAdapter.sol:SinjohPoolsTradeInstantAdapter "$ANF"
v 0x6A4D50D9469fed073c4445Dc4050cd29d1BE25D7 src/SinjohPoolsTradeLBPAdapterFactory.sol:SinjohPoolsTradeLBPAdapterFactory "$ALBPF"
v 0xFcE43DE2ccB8e14b18e33236C04485ebb33F55c6 src/SinjohPoolsTradeLBPAdapter.sol:SinjohPoolsTradeLBPAdapter "$ALBPI"
v 0x3B479157D9c566c00F885BDFfFC22D33193714C2 src/SinjohPoolsTradeBuybackAdapter.sol:SinjohPoolsTradeBuybackAdapter "$ABB"
v 0xF786782FeB44fE7c125D8AB7d570ee7bc129F685 src/SinjohPoolsTradeBuybackAdapter.sol:SinjohPoolsTradeBuybackPriceGuard "$ABG"
v 0x192f324A9BF64C4c9f46aFF77d1A3C8d06c635a5 src/SinjohPoolsTradeSellAdapter.sol:SinjohPoolsTradeSellAdapter "$ASELL"
v 0x4c75DB11b1Eb18251E84A98049918D534176b5a2 src/SinjohPoolsTradeSubjectPriceGuard.sol:SinjohPoolsTradeSubjectPriceGuard "$ASG"
cd ${MERKLE_UPSTREAM_DIR:?set MERKLE_UPSTREAM_DIR to a liquidity-launcher checkout at dd8769c}
forge verify-contract 0x0C8B3e001C8DbBDbe15089c887C9323E097F0a15 src/factories/periphery/MerkleClaimFactory.sol:MerkleClaimFactory --verifier blockscout --verifier-url $VURL 2>&1 | tail -2
echo VERIFY_BATCH_DONE
