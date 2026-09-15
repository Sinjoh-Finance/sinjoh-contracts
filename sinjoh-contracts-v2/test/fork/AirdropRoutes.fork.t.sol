// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { V4SinglePoolAllocationRoute } from "../../src/yield-banks/airdrop/V4SinglePoolAllocationRoute.sol";
import { PonsLifecycleAllocationRoute } from "../../src/yield-banks/airdrop/PonsLifecycleAllocationRoute.sol";
import { PonsV4AllocationRoute } from "../../src/yield-banks/airdrop/PonsV4AllocationRoute.sol";
import { AirdropChainedRoute } from "../../src/yield-banks/airdrop/AirdropChainedRoute.sol";
import { DeltaV3SinglePoolRoute } from "../../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { IYieldBankAllocationRoute } from "../../src/yield-banks/interfaces/IYieldBankAllocationRoute.sol";
interface IAirRouteWETH { function deposit() external payable; }
contract AirdropRoutesForkTest is Test {
    address constant WETH=0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address constant FACTORY=0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address constant PONS=0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant USDG_POOL=0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca;
    string fixture;
    function setUp() public virtual {
        string memory rpc=vm.envOr("ROBINHOOD_MAINNET_RPC_URL",string(""));
        if(bytes(rpc).length==0)vm.skip(true);
        fixture=vm.readFile("deployments/airdrop-research/routes.json");
        vm.createSelectFork(rpc,vm.parseJsonUint(fixture,".block"));
    }
    function testRoute_0_INJOH() public { _rehearse(0, 0.001 ether); }
    function testRoute_1_microduck() public { _rehearse(1, 0.001 ether); }
    function testRoute_2_SHROOM() public { _rehearse(2, 0.001 ether); }
    function testRoute_3_GG() public { _rehearse(3, 0.001 ether); }
    function testRoute_4_MARTIANS() public { _rehearse(4, 0.001 ether); }
    function testRoute_5_GME() public { _rehearse(5, 0.001 ether); }
    function testRoute_6_STONKS() public { _rehearse(6, 0.001 ether); }
    function testRoute_7_CRCL() public { _rehearse(7, 0.001 ether); }
    function testRoute_8_18932() public { _rehearse(8, 0.001 ether); }
    function testRoute_9_MU() public { _rehearse(9, 0.001 ether); }
    function testRoute_10_DINO() public { _rehearse(10, 0.001 ether); }
    function testRoute_11_AGI() public { _rehearse(11, 0.001 ether); }
    function testRoute_12_HUGCOIN() public { _rehearse(12, 0.001 ether); }
    function testRoute_13_VenusCoin() public virtual { _rehearse(13, 0.001 ether); }
    function testRoute_14_BIAO() public { _rehearse(14, 0.001 ether); }
    function testRoute_15_OPTIMUS() public { _rehearse(15, 0.001 ether); }
    function testRoute_16_DICKBUTT() public { _rehearse(16, 0.001 ether); }
    function testRoute_17_urmom() public { _rehearse(17, 0.001 ether); }
    function testRoute_18_BUDDY() public { _rehearse(18, 0.001 ether); }
    function testRoute_19_VERITY() public { _rehearse(19, 0.001 ether); }
    function testRoute_20_SHIT() public { _rehearse(20, 0.001 ether); }
    function testRoute_21_MSTR() public { _rehearse(21, 0.001 ether); }
    function testRoute_22_SHRUB() public { _rehearse(22, 0.001 ether); }
    function testRoute_23_CHIP() public { _rehearse(23, 0.001 ether); }
    function testRoute_24_PONZI() public { _rehearse(24, 0.001 ether); }
    function testRoute_25_JOBS() public { _rehearse(25, 0.001 ether); }
    function testRoute_26_EARLY() public { _rehearse(26, 0.001 ether); }
    function testRoute_27_WADDLES() public { _rehearse(27, 0.001 ether); }
    function testRoute_28_HI() public virtual { _rehearse(28, 0.001 ether); }
    function testRoute_29_NINJA() public { _rehearse(29, 0.001 ether); }
    function testRoute_30_JERK() public { _rehearse(30, 0.001 ether); }
    function testRoute_31_PIG() public virtual { _rehearse(31, 0.001 ether); }
    function testRoute_32_Satori() public { _rehearse(32, 0.001 ether); }
    function testRoute_33_PECCY() public { _rehearse(33, 0.001 ether); }
    function testRoute_34_IRA() public virtual { _rehearse(34, 0.001 ether); }
    function testRoute_35_CRC() public { _rehearse(35, 0.001 ether); }
    function testRoute_36_CAYENNE() public { _rehearse(36, 0.001 ether); }
    function testRoute_37_Figure03() public { _rehearse(37, 0.001 ether); }
    function testRoute_38_STOCKFATHER() public { _rehearse(38, 0.001 ether); }
    function testRoute_39_STARTUP() public { _rehearse(39, 0.001 ether); }
    function testRoute_40_KEYCAT() public { _rehearse(40, 0.001 ether); }
    function testRoute_41_Vlad() public { _rehearse(41, 0.001 ether); }
    function testRoute_42_DIH() public { _rehearse(42, 0.001 ether); }
    function testRoute_43_Finance() public { _rehearse(43, 0.001 ether); }
    function testRoute_44_LOCKIN() public { _rehearse(44, 0.001 ether); }
    function testRoute_45_PLUTOCOIN() public { _rehearse(45, 0.001 ether); }
    function testRoute_46_007() public { _rehearse(46, 0.001 ether); }
    function testRoute_47_PONSDAQ() public { _rehearse(47, 0.001 ether); }
    function testRoute_48_CPU() public { _rehearse(48, 0.001 ether); }
    function testRoute_49_E() public { _rehearse(49, 0.001 ether); }
    function testRoute_50_LARP() public { _rehearse(50, 0.001 ether); }
    function testRoute_51_ELONGATE() public { _rehearse(51, 0.001 ether); }
    function testRoute_52_Rewards() public { _rehearse(52, 0.001 ether); }
    function testRoute_53_SHERIFF() public { _rehearse(53, 0.001 ether); }
    function testRoute_54_VLADCHILL() public { _rehearse(54, 0.001 ether); }
    function testRoute_55_BLACKBERRY() public { _rehearse(55, 0.001 ether); }
    function testRoute_56_DROP() public { _rehearse(56, 0.001 ether); }
    function testRoute_57_ERECT() public { _rehearse(57, 0.001 ether); }
    function testRouteThreeRealTokenBasket() public {
        _rehearse(1,0.002 ether); _rehearse(2,0.003 ether); _rehearse(3,0.005 ether);
    }
    function _rehearse(uint256 index,uint256 amount) internal {
        string memory prefix=string.concat(".rows[",vm.toString(index),"]");
        address subject=vm.parseJsonAddress(fixture,string.concat(prefix,".subject"));
        address quote=vm.parseJsonAddress(fixture,string.concat(prefix,".quote"));
        address pool=vm.parseJsonAddress(fixture,string.concat(prefix,".pool"));
        address bridge=vm.parseJsonAddress(fixture,string.concat(prefix,".bridge"));
        IYieldBankAllocationRoute buyV4; IYieldBankAllocationRoute sellV4;
        bytes32 kind=keccak256(bytes(vm.parseJsonString(fixture,string.concat(prefix,".kind"))));
        if(kind==keccak256("v3")) {buyV4=_v3(pool,WETH,subject);sellV4=_v3(pool,subject,WETH);}
        else if(kind==keccak256("rewards")){
            PoolKey memory key=PoolKey(Currency.wrap(WETH),Currency.wrap(subject),10000,200,IHooks(address(0)));
            buyV4=new V4SinglePoolAllocationRoute(0x8366a39CC670B4001A1121B8F6A443A643e40951,WETH,subject,true,key);
            sellV4=new V4SinglePoolAllocationRoute(0x8366a39CC670B4001A1121B8F6A443A643e40951,WETH,subject,false,key);
        }else{buyV4=new PonsLifecycleAllocationRoute(PONS,WETH,subject,true);sellV4=new PonsLifecycleAllocationRoute(PONS,WETH,subject,false);}
        IYieldBankAllocationRoute buy=buyV4; IYieldBankAllocationRoute sell=sellV4;
        if(quote!=address(0)){
            assertTrue(pool!=address(0),"missing quote bridge");
            address[] memory buys=new address[](bridge==address(0)?2:3);
            address[] memory sells=new address[](buys.length);
            if(bridge==address(0)){
                buys[0]=address(_v3(pool,WETH,quote));buys[1]=address(buyV4);
                sells[0]=address(sellV4);sells[1]=address(_v3(pool,quote,WETH));
            }else{
                buys[0]=address(_v3(USDG_POOL,WETH,bridge));buys[1]=address(_v3(pool,bridge,quote));buys[2]=address(buyV4);
                sells[0]=address(sellV4);sells[1]=address(_v3(pool,quote,bridge));sells[2]=address(_v3(USDG_POOL,bridge,WETH));
            }
            buy=new AirdropChainedRoute(buys);sell=new AirdropChainedRoute(sells);
        }
        vm.deal(address(this),amount);IAirRouteWETH(WETH).deposit{value:amount}();
        uint256 beforeWeth=IERC20(WETH).balanceOf(address(this));
        IERC20(WETH).approve(address(buy),amount);
        uint256 bought=buy.convert(amount,_buyMinimum(subject,amount),address(this),"");
        assertGt(bought,0);assertEq(IERC20(subject).balanceOf(address(this)),bought);
        assertEq(IERC20(WETH).balanceOf(address(this)),beforeWeth-amount);
        IERC20(subject).approve(address(sell),bought);
        uint256 returned=sell.convert(bought,_sellMinimum(subject,bought),address(this),"");
        assertGt(returned,0);assertLe(returned,amount);
        assertEq(IERC20(subject).balanceOf(address(this)),0);
        assertEq(IERC20(WETH).balanceOf(address(this)),beforeWeth-amount+returned);
        assertEq(IERC20(WETH).balanceOf(address(buy)),0);assertEq(IERC20(subject).balanceOf(address(sell)),0);
        assertEq(address(buyV4).balance,0);assertEq(address(sellV4).balance,0);
        emit log_named_uint(string.concat("roundtrip loss bps ",vm.parseJsonString(fixture,string.concat(prefix,".symbol"))), (amount-returned)*10000/amount);
        // Diagnostic roundtrip, not admission: venue fees and price policy are evaluated separately.
    }
    function _v3(address pool,address input,address output) internal returns(DeltaV3SinglePoolRoute){
        return new DeltaV3SinglePoolRoute(pool,FACTORY,input,output,pool.codehash,FACTORY.codehash);
    }
    function _buyMinimum(address,uint256) internal virtual returns(uint256){return 1;}
    function _sellMinimum(address,uint256) internal virtual returns(uint256){return 1;}
}
