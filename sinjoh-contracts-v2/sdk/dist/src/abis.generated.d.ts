export declare const projectLauncherV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "deployer_";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "AIRDROP";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BANDS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BASKET";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "LIQUIDITY";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MULTISIG";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PONS_LOCKER";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PROTOCOL_VERSION";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "RAFFLE";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "ROUTER";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "STAKING";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "TIMELOCK";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "TOKEN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "TREASURY";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "deployer";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract ProjectLaunchDeployerV2";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "hashLaunchConfig";
    readonly inputs: readonly [{
        readonly name: "config";
        readonly type: "tuple";
        readonly internalType: "struct ProjectLaunchConfig";
        readonly components: readonly [{
            readonly name: "creator";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "name";
            readonly type: "string";
            readonly internalType: "string";
        }, {
            readonly name: "symbol";
            readonly type: "string";
            readonly internalType: "string";
        }, {
            readonly name: "totalSupply";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "salt";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "governanceMode";
            readonly type: "uint8";
            readonly internalType: "enum LaunchGovernanceMode";
        }, {
            readonly name: "voteSource";
            readonly type: "uint8";
            readonly internalType: "enum LaunchVoteSource";
        }, {
            readonly name: "modules";
            readonly type: "tuple";
            readonly internalType: "struct ModuleSelection";
            readonly components: readonly [{
                readonly name: "treasury";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "router";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "staking";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "airdrop";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "basket";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "fundingBands";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "raffle";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "liquidity";
                readonly type: "bool";
                readonly internalType: "bool";
            }];
        }, {
            readonly name: "tokenAllocations";
            readonly type: "tuple[]";
            readonly internalType: "struct LaunchTokenAllocation[]";
            readonly components: readonly [{
                readonly name: "recipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "amount";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }];
        }, {
            readonly name: "governance";
            readonly type: "tuple";
            readonly internalType: "struct GovernanceLaunchConfig";
            readonly components: readonly [{
                readonly name: "multisigSigners";
                readonly type: "address[3]";
                readonly internalType: "address[3]";
            }, {
                readonly name: "tokenGovernance";
                readonly type: "tuple";
                readonly internalType: "struct TokenGovernanceConfig";
                readonly components: readonly [{
                    readonly name: "votingDelay";
                    readonly type: "uint48";
                    readonly internalType: "uint48";
                }, {
                    readonly name: "votingPeriod";
                    readonly type: "uint32";
                    readonly internalType: "uint32";
                }, {
                    readonly name: "proposalThresholdBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "quorumBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "timelockDelay";
                    readonly type: "uint48";
                    readonly internalType: "uint48";
                }, {
                    readonly name: "referenceSupply";
                    readonly type: "uint256";
                    readonly internalType: "uint256";
                }];
            }];
        }, {
            readonly name: "staking";
            readonly type: "tuple";
            readonly internalType: "struct StakingLaunchConfig";
            readonly components: readonly [{
                readonly name: "guardian";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "lockDuration";
                readonly type: "uint64";
                readonly internalType: "uint64";
            }];
        }, {
            readonly name: "airdrop";
            readonly type: "tuple";
            readonly internalType: "struct AirdropLaunchConfig";
            readonly components: readonly [{
                readonly name: "attestor";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "eligibilityMode";
                readonly type: "uint8";
                readonly internalType: "enum AirdropEligibilityMode";
            }, {
                readonly name: "additionalExclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "treasury";
            readonly type: "tuple";
            readonly internalType: "struct TreasuryLaunchConfig";
            readonly components: readonly [{
                readonly name: "basketAllocationBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "basketRouteAssets";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "routerRoutes";
            readonly type: "tuple[]";
            readonly internalType: "struct RouterRouteInput[]";
            readonly components: readonly [{
                readonly name: "inputAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "actions";
                readonly type: "tuple[]";
                readonly internalType: "struct RouterAction[]";
                readonly components: readonly [{
                    readonly name: "actionType";
                    readonly type: "uint8";
                    readonly internalType: "enum RouterActionType";
                }, {
                    readonly name: "allocationBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "recipient";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "adapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "priceGuard";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "actionConfig";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }];
            }];
        }, {
            readonly name: "basket";
            readonly type: "tuple";
            readonly internalType: "struct BasketConfig";
            readonly components: readonly [{
                readonly name: "cadence";
                readonly type: "uint8";
                readonly internalType: "enum BasketHarvestCadence";
            }, {
                readonly name: "eligibilityMode";
                readonly type: "uint8";
                readonly internalType: "enum BasketEligibilityMode";
            }, {
                readonly name: "governanceUpdatesEnabled";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "burnTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "burnTaxDestination";
                readonly type: "uint8";
                readonly internalType: "enum BasketBurnTaxDestination";
            }, {
                readonly name: "burnPriceSubject";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "airdropAccountConfig";
                readonly type: "bytes";
                readonly internalType: "bytes";
            }, {
                readonly name: "allocation";
                readonly type: "tuple";
                readonly internalType: "struct BasketAllocationConfig";
                readonly components: readonly [{
                    readonly name: "inputAssets";
                    readonly type: "address[]";
                    readonly internalType: "address[]";
                }, {
                    readonly name: "targets";
                    readonly type: "tuple[]";
                    readonly internalType: "struct BasketTarget[]";
                    readonly components: readonly [{
                        readonly name: "depositAsset";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "yieldAdapter";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "targetWeightBps";
                        readonly type: "uint16";
                        readonly internalType: "uint16";
                    }, {
                        readonly name: "rewardAssets";
                        readonly type: "address[]";
                        readonly internalType: "address[]";
                    }, {
                        readonly name: "yieldApprovalProof";
                        readonly type: "bytes32[]";
                        readonly internalType: "bytes32[]";
                    }];
                }, {
                    readonly name: "swapLegs";
                    readonly type: "tuple[]";
                    readonly internalType: "struct BasketSwapLeg[]";
                    readonly components: readonly [{
                        readonly name: "inputAsset";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "targetIndex";
                        readonly type: "uint8";
                        readonly internalType: "uint8";
                    }, {
                        readonly name: "swapAdapter";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "priceGuard";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "maxSlippageBps";
                        readonly type: "uint16";
                        readonly internalType: "uint16";
                    }, {
                        readonly name: "routeData";
                        readonly type: "bytes";
                        readonly internalType: "bytes";
                    }, {
                        readonly name: "approvalProof";
                        readonly type: "bytes32[]";
                        readonly internalType: "bytes32[]";
                    }];
                }];
            }];
        }, {
            readonly name: "basketERC4626Vaults";
            readonly type: "address[]";
            readonly internalType: "address[]";
        }, {
            readonly name: "bands";
            readonly type: "tuple";
            readonly internalType: "struct BandsLaunchConfig";
            readonly components: readonly [{
                readonly name: "quoteAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "marketCapGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "positionAdapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "twapWindow";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "quoteUsdOracle";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tickReferenceQuoteUsdE8";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "confirmationPeriod";
                readonly type: "uint48";
                readonly internalType: "uint48";
            }, {
                readonly name: "maximumObservationAge";
                readonly type: "uint48";
                readonly internalType: "uint48";
            }, {
                readonly name: "integrationApprovalProof";
                readonly type: "bytes32[]";
                readonly internalType: "bytes32[]";
            }];
        }, {
            readonly name: "raffle";
            readonly type: "tuple";
            readonly internalType: "struct RaffleTypes.Config";
            readonly components: readonly [{
                readonly name: "creator";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "attestor";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "randomness";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "prizeAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "protocolFeeRecipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "taxRecipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tokensPerTicket";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "maxTicketsPerHolder";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "minPrize";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "maxPrize";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "prizeBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "recipientTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "recycleTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "minConfirmations";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "winnersPerRound";
                readonly type: "uint8";
                readonly internalType: "uint8";
            }, {
                readonly name: "minRoundInterval";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "weightWindowBlocks";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "randomnessTimeout";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "claimWindow";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "basis";
                readonly type: "uint8";
                readonly internalType: "enum RaffleTypes.TicketBasis";
            }, {
                readonly name: "exclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }, {
                readonly name: "stockRewards";
                readonly type: "tuple[]";
                readonly internalType: "struct RaffleTypes.StockReward[]";
                readonly components: readonly [{
                    readonly name: "asset";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "swapAdapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "priceGuard";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "routeData";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }, {
                    readonly name: "guardData";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }];
            }];
        }, {
            readonly name: "launchProfile";
            readonly type: "tuple";
            readonly internalType: "struct LaunchProfileConfig";
            readonly components: readonly [{
                readonly name: "canonicalPool";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "additionalCustodyExclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "metadataURI";
            readonly type: "string";
            readonly internalType: "string";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "launch";
    readonly inputs: readonly [{
        readonly name: "config";
        readonly type: "tuple";
        readonly internalType: "struct ProjectLaunchConfig";
        readonly components: readonly [{
            readonly name: "creator";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "name";
            readonly type: "string";
            readonly internalType: "string";
        }, {
            readonly name: "symbol";
            readonly type: "string";
            readonly internalType: "string";
        }, {
            readonly name: "totalSupply";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "salt";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "governanceMode";
            readonly type: "uint8";
            readonly internalType: "enum LaunchGovernanceMode";
        }, {
            readonly name: "voteSource";
            readonly type: "uint8";
            readonly internalType: "enum LaunchVoteSource";
        }, {
            readonly name: "modules";
            readonly type: "tuple";
            readonly internalType: "struct ModuleSelection";
            readonly components: readonly [{
                readonly name: "treasury";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "router";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "staking";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "airdrop";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "basket";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "fundingBands";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "raffle";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "liquidity";
                readonly type: "bool";
                readonly internalType: "bool";
            }];
        }, {
            readonly name: "tokenAllocations";
            readonly type: "tuple[]";
            readonly internalType: "struct LaunchTokenAllocation[]";
            readonly components: readonly [{
                readonly name: "recipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "amount";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }];
        }, {
            readonly name: "governance";
            readonly type: "tuple";
            readonly internalType: "struct GovernanceLaunchConfig";
            readonly components: readonly [{
                readonly name: "multisigSigners";
                readonly type: "address[3]";
                readonly internalType: "address[3]";
            }, {
                readonly name: "tokenGovernance";
                readonly type: "tuple";
                readonly internalType: "struct TokenGovernanceConfig";
                readonly components: readonly [{
                    readonly name: "votingDelay";
                    readonly type: "uint48";
                    readonly internalType: "uint48";
                }, {
                    readonly name: "votingPeriod";
                    readonly type: "uint32";
                    readonly internalType: "uint32";
                }, {
                    readonly name: "proposalThresholdBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "quorumBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "timelockDelay";
                    readonly type: "uint48";
                    readonly internalType: "uint48";
                }, {
                    readonly name: "referenceSupply";
                    readonly type: "uint256";
                    readonly internalType: "uint256";
                }];
            }];
        }, {
            readonly name: "staking";
            readonly type: "tuple";
            readonly internalType: "struct StakingLaunchConfig";
            readonly components: readonly [{
                readonly name: "guardian";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "lockDuration";
                readonly type: "uint64";
                readonly internalType: "uint64";
            }];
        }, {
            readonly name: "airdrop";
            readonly type: "tuple";
            readonly internalType: "struct AirdropLaunchConfig";
            readonly components: readonly [{
                readonly name: "attestor";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "eligibilityMode";
                readonly type: "uint8";
                readonly internalType: "enum AirdropEligibilityMode";
            }, {
                readonly name: "additionalExclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "treasury";
            readonly type: "tuple";
            readonly internalType: "struct TreasuryLaunchConfig";
            readonly components: readonly [{
                readonly name: "basketAllocationBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "basketRouteAssets";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "routerRoutes";
            readonly type: "tuple[]";
            readonly internalType: "struct RouterRouteInput[]";
            readonly components: readonly [{
                readonly name: "inputAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "actions";
                readonly type: "tuple[]";
                readonly internalType: "struct RouterAction[]";
                readonly components: readonly [{
                    readonly name: "actionType";
                    readonly type: "uint8";
                    readonly internalType: "enum RouterActionType";
                }, {
                    readonly name: "allocationBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "recipient";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "adapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "priceGuard";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "actionConfig";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }];
            }];
        }, {
            readonly name: "basket";
            readonly type: "tuple";
            readonly internalType: "struct BasketConfig";
            readonly components: readonly [{
                readonly name: "cadence";
                readonly type: "uint8";
                readonly internalType: "enum BasketHarvestCadence";
            }, {
                readonly name: "eligibilityMode";
                readonly type: "uint8";
                readonly internalType: "enum BasketEligibilityMode";
            }, {
                readonly name: "governanceUpdatesEnabled";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "burnTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "burnTaxDestination";
                readonly type: "uint8";
                readonly internalType: "enum BasketBurnTaxDestination";
            }, {
                readonly name: "burnPriceSubject";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "airdropAccountConfig";
                readonly type: "bytes";
                readonly internalType: "bytes";
            }, {
                readonly name: "allocation";
                readonly type: "tuple";
                readonly internalType: "struct BasketAllocationConfig";
                readonly components: readonly [{
                    readonly name: "inputAssets";
                    readonly type: "address[]";
                    readonly internalType: "address[]";
                }, {
                    readonly name: "targets";
                    readonly type: "tuple[]";
                    readonly internalType: "struct BasketTarget[]";
                    readonly components: readonly [{
                        readonly name: "depositAsset";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "yieldAdapter";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "targetWeightBps";
                        readonly type: "uint16";
                        readonly internalType: "uint16";
                    }, {
                        readonly name: "rewardAssets";
                        readonly type: "address[]";
                        readonly internalType: "address[]";
                    }, {
                        readonly name: "yieldApprovalProof";
                        readonly type: "bytes32[]";
                        readonly internalType: "bytes32[]";
                    }];
                }, {
                    readonly name: "swapLegs";
                    readonly type: "tuple[]";
                    readonly internalType: "struct BasketSwapLeg[]";
                    readonly components: readonly [{
                        readonly name: "inputAsset";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "targetIndex";
                        readonly type: "uint8";
                        readonly internalType: "uint8";
                    }, {
                        readonly name: "swapAdapter";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "priceGuard";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "maxSlippageBps";
                        readonly type: "uint16";
                        readonly internalType: "uint16";
                    }, {
                        readonly name: "routeData";
                        readonly type: "bytes";
                        readonly internalType: "bytes";
                    }, {
                        readonly name: "approvalProof";
                        readonly type: "bytes32[]";
                        readonly internalType: "bytes32[]";
                    }];
                }];
            }];
        }, {
            readonly name: "basketERC4626Vaults";
            readonly type: "address[]";
            readonly internalType: "address[]";
        }, {
            readonly name: "bands";
            readonly type: "tuple";
            readonly internalType: "struct BandsLaunchConfig";
            readonly components: readonly [{
                readonly name: "quoteAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "marketCapGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "positionAdapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "twapWindow";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "quoteUsdOracle";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tickReferenceQuoteUsdE8";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "confirmationPeriod";
                readonly type: "uint48";
                readonly internalType: "uint48";
            }, {
                readonly name: "maximumObservationAge";
                readonly type: "uint48";
                readonly internalType: "uint48";
            }, {
                readonly name: "integrationApprovalProof";
                readonly type: "bytes32[]";
                readonly internalType: "bytes32[]";
            }];
        }, {
            readonly name: "raffle";
            readonly type: "tuple";
            readonly internalType: "struct RaffleTypes.Config";
            readonly components: readonly [{
                readonly name: "creator";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "attestor";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "randomness";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "prizeAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "protocolFeeRecipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "taxRecipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tokensPerTicket";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "maxTicketsPerHolder";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "minPrize";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "maxPrize";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "prizeBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "recipientTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "recycleTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "minConfirmations";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "winnersPerRound";
                readonly type: "uint8";
                readonly internalType: "uint8";
            }, {
                readonly name: "minRoundInterval";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "weightWindowBlocks";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "randomnessTimeout";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "claimWindow";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "basis";
                readonly type: "uint8";
                readonly internalType: "enum RaffleTypes.TicketBasis";
            }, {
                readonly name: "exclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }, {
                readonly name: "stockRewards";
                readonly type: "tuple[]";
                readonly internalType: "struct RaffleTypes.StockReward[]";
                readonly components: readonly [{
                    readonly name: "asset";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "swapAdapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "priceGuard";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "routeData";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }, {
                    readonly name: "guardData";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }];
            }];
        }, {
            readonly name: "launchProfile";
            readonly type: "tuple";
            readonly internalType: "struct LaunchProfileConfig";
            readonly components: readonly [{
                readonly name: "canonicalPool";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "additionalCustodyExclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "metadataURI";
            readonly type: "string";
            readonly internalType: "string";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "preview";
        readonly type: "tuple";
        readonly internalType: "struct ProjectLaunchPreview";
        readonly components: readonly [{
            readonly name: "launchConfigHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "projectId";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "enabledModules";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "addresses";
            readonly type: "tuple";
            readonly internalType: "struct ProjectLaunchAddresses";
            readonly components: readonly [{
                readonly name: "subject";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "controller";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "multisigAccount";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tokenGovernor";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tokenTimelock";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "voteSource";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "treasury";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "router";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "stakingPool";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "posNft";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "airdrop";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "raffle";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "liquidityManager";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "fundingBands";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "fundingBandMarketCapGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "fundingBandPositionAdapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "basketManager";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "primaryBasketVault";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "basketYieldAdapters";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }, {
                readonly name: "primaryBasketId";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }];
        }];
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "predictLaunch";
    readonly inputs: readonly [{
        readonly name: "config";
        readonly type: "tuple";
        readonly internalType: "struct ProjectLaunchConfig";
        readonly components: readonly [{
            readonly name: "creator";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "name";
            readonly type: "string";
            readonly internalType: "string";
        }, {
            readonly name: "symbol";
            readonly type: "string";
            readonly internalType: "string";
        }, {
            readonly name: "totalSupply";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "salt";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "governanceMode";
            readonly type: "uint8";
            readonly internalType: "enum LaunchGovernanceMode";
        }, {
            readonly name: "voteSource";
            readonly type: "uint8";
            readonly internalType: "enum LaunchVoteSource";
        }, {
            readonly name: "modules";
            readonly type: "tuple";
            readonly internalType: "struct ModuleSelection";
            readonly components: readonly [{
                readonly name: "treasury";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "router";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "staking";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "airdrop";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "basket";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "fundingBands";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "raffle";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "liquidity";
                readonly type: "bool";
                readonly internalType: "bool";
            }];
        }, {
            readonly name: "tokenAllocations";
            readonly type: "tuple[]";
            readonly internalType: "struct LaunchTokenAllocation[]";
            readonly components: readonly [{
                readonly name: "recipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "amount";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }];
        }, {
            readonly name: "governance";
            readonly type: "tuple";
            readonly internalType: "struct GovernanceLaunchConfig";
            readonly components: readonly [{
                readonly name: "multisigSigners";
                readonly type: "address[3]";
                readonly internalType: "address[3]";
            }, {
                readonly name: "tokenGovernance";
                readonly type: "tuple";
                readonly internalType: "struct TokenGovernanceConfig";
                readonly components: readonly [{
                    readonly name: "votingDelay";
                    readonly type: "uint48";
                    readonly internalType: "uint48";
                }, {
                    readonly name: "votingPeriod";
                    readonly type: "uint32";
                    readonly internalType: "uint32";
                }, {
                    readonly name: "proposalThresholdBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "quorumBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "timelockDelay";
                    readonly type: "uint48";
                    readonly internalType: "uint48";
                }, {
                    readonly name: "referenceSupply";
                    readonly type: "uint256";
                    readonly internalType: "uint256";
                }];
            }];
        }, {
            readonly name: "staking";
            readonly type: "tuple";
            readonly internalType: "struct StakingLaunchConfig";
            readonly components: readonly [{
                readonly name: "guardian";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "lockDuration";
                readonly type: "uint64";
                readonly internalType: "uint64";
            }];
        }, {
            readonly name: "airdrop";
            readonly type: "tuple";
            readonly internalType: "struct AirdropLaunchConfig";
            readonly components: readonly [{
                readonly name: "attestor";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "eligibilityMode";
                readonly type: "uint8";
                readonly internalType: "enum AirdropEligibilityMode";
            }, {
                readonly name: "additionalExclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "treasury";
            readonly type: "tuple";
            readonly internalType: "struct TreasuryLaunchConfig";
            readonly components: readonly [{
                readonly name: "basketAllocationBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "basketRouteAssets";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "routerRoutes";
            readonly type: "tuple[]";
            readonly internalType: "struct RouterRouteInput[]";
            readonly components: readonly [{
                readonly name: "inputAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "actions";
                readonly type: "tuple[]";
                readonly internalType: "struct RouterAction[]";
                readonly components: readonly [{
                    readonly name: "actionType";
                    readonly type: "uint8";
                    readonly internalType: "enum RouterActionType";
                }, {
                    readonly name: "allocationBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "recipient";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "adapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "priceGuard";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "actionConfig";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }];
            }];
        }, {
            readonly name: "basket";
            readonly type: "tuple";
            readonly internalType: "struct BasketConfig";
            readonly components: readonly [{
                readonly name: "cadence";
                readonly type: "uint8";
                readonly internalType: "enum BasketHarvestCadence";
            }, {
                readonly name: "eligibilityMode";
                readonly type: "uint8";
                readonly internalType: "enum BasketEligibilityMode";
            }, {
                readonly name: "governanceUpdatesEnabled";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "burnTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "burnTaxDestination";
                readonly type: "uint8";
                readonly internalType: "enum BasketBurnTaxDestination";
            }, {
                readonly name: "burnPriceSubject";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "airdropAccountConfig";
                readonly type: "bytes";
                readonly internalType: "bytes";
            }, {
                readonly name: "allocation";
                readonly type: "tuple";
                readonly internalType: "struct BasketAllocationConfig";
                readonly components: readonly [{
                    readonly name: "inputAssets";
                    readonly type: "address[]";
                    readonly internalType: "address[]";
                }, {
                    readonly name: "targets";
                    readonly type: "tuple[]";
                    readonly internalType: "struct BasketTarget[]";
                    readonly components: readonly [{
                        readonly name: "depositAsset";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "yieldAdapter";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "targetWeightBps";
                        readonly type: "uint16";
                        readonly internalType: "uint16";
                    }, {
                        readonly name: "rewardAssets";
                        readonly type: "address[]";
                        readonly internalType: "address[]";
                    }, {
                        readonly name: "yieldApprovalProof";
                        readonly type: "bytes32[]";
                        readonly internalType: "bytes32[]";
                    }];
                }, {
                    readonly name: "swapLegs";
                    readonly type: "tuple[]";
                    readonly internalType: "struct BasketSwapLeg[]";
                    readonly components: readonly [{
                        readonly name: "inputAsset";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "targetIndex";
                        readonly type: "uint8";
                        readonly internalType: "uint8";
                    }, {
                        readonly name: "swapAdapter";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "priceGuard";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "maxSlippageBps";
                        readonly type: "uint16";
                        readonly internalType: "uint16";
                    }, {
                        readonly name: "routeData";
                        readonly type: "bytes";
                        readonly internalType: "bytes";
                    }, {
                        readonly name: "approvalProof";
                        readonly type: "bytes32[]";
                        readonly internalType: "bytes32[]";
                    }];
                }];
            }];
        }, {
            readonly name: "basketERC4626Vaults";
            readonly type: "address[]";
            readonly internalType: "address[]";
        }, {
            readonly name: "bands";
            readonly type: "tuple";
            readonly internalType: "struct BandsLaunchConfig";
            readonly components: readonly [{
                readonly name: "quoteAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "marketCapGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "positionAdapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "twapWindow";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "quoteUsdOracle";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tickReferenceQuoteUsdE8";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "confirmationPeriod";
                readonly type: "uint48";
                readonly internalType: "uint48";
            }, {
                readonly name: "maximumObservationAge";
                readonly type: "uint48";
                readonly internalType: "uint48";
            }, {
                readonly name: "integrationApprovalProof";
                readonly type: "bytes32[]";
                readonly internalType: "bytes32[]";
            }];
        }, {
            readonly name: "raffle";
            readonly type: "tuple";
            readonly internalType: "struct RaffleTypes.Config";
            readonly components: readonly [{
                readonly name: "creator";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "attestor";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "randomness";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "prizeAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "protocolFeeRecipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "taxRecipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tokensPerTicket";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "maxTicketsPerHolder";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "minPrize";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "maxPrize";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "prizeBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "recipientTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "recycleTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "minConfirmations";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "winnersPerRound";
                readonly type: "uint8";
                readonly internalType: "uint8";
            }, {
                readonly name: "minRoundInterval";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "weightWindowBlocks";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "randomnessTimeout";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "claimWindow";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "basis";
                readonly type: "uint8";
                readonly internalType: "enum RaffleTypes.TicketBasis";
            }, {
                readonly name: "exclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }, {
                readonly name: "stockRewards";
                readonly type: "tuple[]";
                readonly internalType: "struct RaffleTypes.StockReward[]";
                readonly components: readonly [{
                    readonly name: "asset";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "swapAdapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "priceGuard";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "routeData";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }, {
                    readonly name: "guardData";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }];
            }];
        }, {
            readonly name: "launchProfile";
            readonly type: "tuple";
            readonly internalType: "struct LaunchProfileConfig";
            readonly components: readonly [{
                readonly name: "canonicalPool";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "additionalCustodyExclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "metadataURI";
            readonly type: "string";
            readonly internalType: "string";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct ProjectLaunchPreview";
        readonly components: readonly [{
            readonly name: "launchConfigHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "projectId";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "enabledModules";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "addresses";
            readonly type: "tuple";
            readonly internalType: "struct ProjectLaunchAddresses";
            readonly components: readonly [{
                readonly name: "subject";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "controller";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "multisigAccount";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tokenGovernor";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tokenTimelock";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "voteSource";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "treasury";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "router";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "stakingPool";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "posNft";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "airdrop";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "raffle";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "liquidityManager";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "fundingBands";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "fundingBandMarketCapGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "fundingBandPositionAdapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "basketManager";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "primaryBasketVault";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "basketYieldAdapters";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }, {
                readonly name: "primaryBasketId";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }];
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "predictModuleAddress";
    readonly inputs: readonly [{
        readonly name: "creator";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "userSalt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "moduleKey";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract ProjectRegistryV2";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "validateLaunchConfig";
    readonly inputs: readonly [{
        readonly name: "config";
        readonly type: "tuple";
        readonly internalType: "struct ProjectLaunchConfig";
        readonly components: readonly [{
            readonly name: "creator";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "name";
            readonly type: "string";
            readonly internalType: "string";
        }, {
            readonly name: "symbol";
            readonly type: "string";
            readonly internalType: "string";
        }, {
            readonly name: "totalSupply";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "salt";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "governanceMode";
            readonly type: "uint8";
            readonly internalType: "enum LaunchGovernanceMode";
        }, {
            readonly name: "voteSource";
            readonly type: "uint8";
            readonly internalType: "enum LaunchVoteSource";
        }, {
            readonly name: "modules";
            readonly type: "tuple";
            readonly internalType: "struct ModuleSelection";
            readonly components: readonly [{
                readonly name: "treasury";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "router";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "staking";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "airdrop";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "basket";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "fundingBands";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "raffle";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "liquidity";
                readonly type: "bool";
                readonly internalType: "bool";
            }];
        }, {
            readonly name: "tokenAllocations";
            readonly type: "tuple[]";
            readonly internalType: "struct LaunchTokenAllocation[]";
            readonly components: readonly [{
                readonly name: "recipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "amount";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }];
        }, {
            readonly name: "governance";
            readonly type: "tuple";
            readonly internalType: "struct GovernanceLaunchConfig";
            readonly components: readonly [{
                readonly name: "multisigSigners";
                readonly type: "address[3]";
                readonly internalType: "address[3]";
            }, {
                readonly name: "tokenGovernance";
                readonly type: "tuple";
                readonly internalType: "struct TokenGovernanceConfig";
                readonly components: readonly [{
                    readonly name: "votingDelay";
                    readonly type: "uint48";
                    readonly internalType: "uint48";
                }, {
                    readonly name: "votingPeriod";
                    readonly type: "uint32";
                    readonly internalType: "uint32";
                }, {
                    readonly name: "proposalThresholdBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "quorumBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "timelockDelay";
                    readonly type: "uint48";
                    readonly internalType: "uint48";
                }, {
                    readonly name: "referenceSupply";
                    readonly type: "uint256";
                    readonly internalType: "uint256";
                }];
            }];
        }, {
            readonly name: "staking";
            readonly type: "tuple";
            readonly internalType: "struct StakingLaunchConfig";
            readonly components: readonly [{
                readonly name: "guardian";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "lockDuration";
                readonly type: "uint64";
                readonly internalType: "uint64";
            }];
        }, {
            readonly name: "airdrop";
            readonly type: "tuple";
            readonly internalType: "struct AirdropLaunchConfig";
            readonly components: readonly [{
                readonly name: "attestor";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "eligibilityMode";
                readonly type: "uint8";
                readonly internalType: "enum AirdropEligibilityMode";
            }, {
                readonly name: "additionalExclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "treasury";
            readonly type: "tuple";
            readonly internalType: "struct TreasuryLaunchConfig";
            readonly components: readonly [{
                readonly name: "basketAllocationBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "basketRouteAssets";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "routerRoutes";
            readonly type: "tuple[]";
            readonly internalType: "struct RouterRouteInput[]";
            readonly components: readonly [{
                readonly name: "inputAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "actions";
                readonly type: "tuple[]";
                readonly internalType: "struct RouterAction[]";
                readonly components: readonly [{
                    readonly name: "actionType";
                    readonly type: "uint8";
                    readonly internalType: "enum RouterActionType";
                }, {
                    readonly name: "allocationBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "recipient";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "adapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "priceGuard";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "actionConfig";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }];
            }];
        }, {
            readonly name: "basket";
            readonly type: "tuple";
            readonly internalType: "struct BasketConfig";
            readonly components: readonly [{
                readonly name: "cadence";
                readonly type: "uint8";
                readonly internalType: "enum BasketHarvestCadence";
            }, {
                readonly name: "eligibilityMode";
                readonly type: "uint8";
                readonly internalType: "enum BasketEligibilityMode";
            }, {
                readonly name: "governanceUpdatesEnabled";
                readonly type: "bool";
                readonly internalType: "bool";
            }, {
                readonly name: "burnTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "burnTaxDestination";
                readonly type: "uint8";
                readonly internalType: "enum BasketBurnTaxDestination";
            }, {
                readonly name: "burnPriceSubject";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "airdropAccountConfig";
                readonly type: "bytes";
                readonly internalType: "bytes";
            }, {
                readonly name: "allocation";
                readonly type: "tuple";
                readonly internalType: "struct BasketAllocationConfig";
                readonly components: readonly [{
                    readonly name: "inputAssets";
                    readonly type: "address[]";
                    readonly internalType: "address[]";
                }, {
                    readonly name: "targets";
                    readonly type: "tuple[]";
                    readonly internalType: "struct BasketTarget[]";
                    readonly components: readonly [{
                        readonly name: "depositAsset";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "yieldAdapter";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "targetWeightBps";
                        readonly type: "uint16";
                        readonly internalType: "uint16";
                    }, {
                        readonly name: "rewardAssets";
                        readonly type: "address[]";
                        readonly internalType: "address[]";
                    }, {
                        readonly name: "yieldApprovalProof";
                        readonly type: "bytes32[]";
                        readonly internalType: "bytes32[]";
                    }];
                }, {
                    readonly name: "swapLegs";
                    readonly type: "tuple[]";
                    readonly internalType: "struct BasketSwapLeg[]";
                    readonly components: readonly [{
                        readonly name: "inputAsset";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "targetIndex";
                        readonly type: "uint8";
                        readonly internalType: "uint8";
                    }, {
                        readonly name: "swapAdapter";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "priceGuard";
                        readonly type: "address";
                        readonly internalType: "address";
                    }, {
                        readonly name: "maxSlippageBps";
                        readonly type: "uint16";
                        readonly internalType: "uint16";
                    }, {
                        readonly name: "routeData";
                        readonly type: "bytes";
                        readonly internalType: "bytes";
                    }, {
                        readonly name: "approvalProof";
                        readonly type: "bytes32[]";
                        readonly internalType: "bytes32[]";
                    }];
                }];
            }];
        }, {
            readonly name: "basketERC4626Vaults";
            readonly type: "address[]";
            readonly internalType: "address[]";
        }, {
            readonly name: "bands";
            readonly type: "tuple";
            readonly internalType: "struct BandsLaunchConfig";
            readonly components: readonly [{
                readonly name: "quoteAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "marketCapGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "positionAdapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "twapWindow";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "quoteUsdOracle";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tickReferenceQuoteUsdE8";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "confirmationPeriod";
                readonly type: "uint48";
                readonly internalType: "uint48";
            }, {
                readonly name: "maximumObservationAge";
                readonly type: "uint48";
                readonly internalType: "uint48";
            }, {
                readonly name: "integrationApprovalProof";
                readonly type: "bytes32[]";
                readonly internalType: "bytes32[]";
            }];
        }, {
            readonly name: "raffle";
            readonly type: "tuple";
            readonly internalType: "struct RaffleTypes.Config";
            readonly components: readonly [{
                readonly name: "creator";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "attestor";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "randomness";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "prizeAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "protocolFeeRecipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "taxRecipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tokensPerTicket";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "maxTicketsPerHolder";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "minPrize";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "maxPrize";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "prizeBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "recipientTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "recycleTaxBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "minConfirmations";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "winnersPerRound";
                readonly type: "uint8";
                readonly internalType: "uint8";
            }, {
                readonly name: "minRoundInterval";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "weightWindowBlocks";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "randomnessTimeout";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "claimWindow";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "basis";
                readonly type: "uint8";
                readonly internalType: "enum RaffleTypes.TicketBasis";
            }, {
                readonly name: "exclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }, {
                readonly name: "stockRewards";
                readonly type: "tuple[]";
                readonly internalType: "struct RaffleTypes.StockReward[]";
                readonly components: readonly [{
                    readonly name: "asset";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "swapAdapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "priceGuard";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "routeData";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }, {
                    readonly name: "guardData";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }];
            }];
        }, {
            readonly name: "launchProfile";
            readonly type: "tuple";
            readonly internalType: "struct LaunchProfileConfig";
            readonly components: readonly [{
                readonly name: "canonicalPool";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "additionalCustodyExclusions";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }];
        }, {
            readonly name: "metadataURI";
            readonly type: "string";
            readonly internalType: "string";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct ProjectLaunchPreview";
        readonly components: readonly [{
            readonly name: "launchConfigHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "projectId";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "enabledModules";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "addresses";
            readonly type: "tuple";
            readonly internalType: "struct ProjectLaunchAddresses";
            readonly components: readonly [{
                readonly name: "subject";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "controller";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "multisigAccount";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tokenGovernor";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "tokenTimelock";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "voteSource";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "treasury";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "router";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "stakingPool";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "posNft";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "airdrop";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "raffle";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "liquidityManager";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "fundingBands";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "fundingBandMarketCapGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "fundingBandPositionAdapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "basketManager";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "primaryBasketVault";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "basketYieldAdapters";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }, {
                readonly name: "primaryBasketId";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }];
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "ProjectLaunchCompleted";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "creator";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "controller";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "launchConfigHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }, {
        readonly name: "enabledModules";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "AllocationToCustody";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "CreatorExcluded";
    readonly inputs: readonly [{
        readonly name: "creator";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "CreatorMustLaunch";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "creator";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "DuplicateTokenAllocation";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAirdropConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidBandsConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidBasketConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidCreator";
    readonly inputs: readonly [{
        readonly name: "creator";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidGovernanceConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidMetadataURI";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidModuleDependencies";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidRaffleConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidReleaseComponent";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRouterPlaceholder";
    readonly inputs: readonly [{
        readonly name: "routeIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "actionIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidStakingConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidTokenAllocation";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTokenAllocations";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidTokenMetadata";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidTotalSupply";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTreasuryConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ModuleDeploymentMismatch";
    readonly inputs: readonly [{
        readonly name: "moduleKey";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "deployed";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ReentrancyGuardReentrantCall";
    readonly inputs: readonly [];
}];
export declare const projectRegistryV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "launcher_";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_METADATA_URI_BYTES";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MODULE_AIRDROP";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MODULE_BASKET";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MODULE_FUNDING_BANDS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MODULE_LIQUIDITY";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MODULE_RAFFLE";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MODULE_ROUTER";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MODULE_STAKING";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MODULE_TREASURY";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PROTOCOL_VERSION";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "SUPPORTED_MODULES";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "hasModule";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "moduleBit";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isProjectModule";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "launchConfigHash";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "configHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "launcher";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "metadataHash";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "hash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "metadataURI";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "metadataVersion";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "moduleBits";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "module";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "bits";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "project";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct ProjectRegistryV2.ProjectRecord";
        readonly components: readonly [{
            readonly name: "projectId";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "subject";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "creator";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "governanceMode";
            readonly type: "uint8";
            readonly internalType: "enum ProjectRegistryV2.GovernanceMode";
        }, {
            readonly name: "controller";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "multisigAccount";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tokenGovernor";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tokenTimelock";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "voteSource";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "treasury";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "router";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "stakingPool";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "posNft";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "airdrop";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "raffle";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "liquidityManager";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "fundingBands";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "basketManager";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "primaryBasketId";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "canonicalPool";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "referenceSupply";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "launchedAt";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "protocolVersion";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "enabledModules";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectBySubject";
    readonly inputs: readonly [{
        readonly name: "subject";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct ProjectRegistryV2.ProjectRecord";
        readonly components: readonly [{
            readonly name: "projectId";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "subject";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "creator";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "governanceMode";
            readonly type: "uint8";
            readonly internalType: "enum ProjectRegistryV2.GovernanceMode";
        }, {
            readonly name: "controller";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "multisigAccount";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tokenGovernor";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tokenTimelock";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "voteSource";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "treasury";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "router";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "stakingPool";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "posNft";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "airdrop";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "raffle";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "liquidityManager";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "fundingBands";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "basketManager";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "primaryBasketId";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "canonicalPool";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "referenceSupply";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "launchedAt";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "protocolVersion";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "enabledModules";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectCount";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectIdAt";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectIdBySubject";
    readonly inputs: readonly [{
        readonly name: "subject";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "registerProject";
    readonly inputs: readonly [{
        readonly name: "registration";
        readonly type: "tuple";
        readonly internalType: "struct ProjectRegistryV2.ProjectRegistration";
        readonly components: readonly [{
            readonly name: "subject";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "creator";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "governanceMode";
            readonly type: "uint8";
            readonly internalType: "enum ProjectRegistryV2.GovernanceMode";
        }, {
            readonly name: "controller";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "multisigAccount";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tokenGovernor";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tokenTimelock";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "voteSource";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "treasury";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "router";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "stakingPool";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "posNft";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "airdrop";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "raffle";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "liquidityManager";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "fundingBands";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "basketManager";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "primaryBasketId";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "canonicalPool";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "referenceSupply";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "enabledModules";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }, {
        readonly name: "configHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "initialMetadataURI";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly outputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "updateMetadataURI";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "newMetadataURI";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "event";
    readonly name: "ProjectLaunched";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "creator";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "controller";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "launchConfigHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }, {
        readonly name: "enabledModules";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProjectMetadataUpdated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "metadataHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProjectModules";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "treasury";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "router";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "stakingPool";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "posNft";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "airdrop";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "raffle";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "liquidityManager";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "fundingBands";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "basketManager";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "primaryBasketId";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "InvalidController";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidCreator";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidEnabledModules";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidGovernanceConfiguration";
    readonly inputs: readonly [{
        readonly name: "mode";
        readonly type: "uint8";
        readonly internalType: "enum ProjectRegistryV2.GovernanceMode";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidLauncher";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidModule";
    readonly inputs: readonly [{
        readonly name: "moduleBit";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidModuleDependencies";
    readonly inputs: readonly [{
        readonly name: "enabledModules";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidPoSNFT";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidPrimaryBasket";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidReferenceSupply";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidVoteSource";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "MetadataURITooLong";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "maximum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "MetadataUnchanged";
    readonly inputs: readonly [{
        readonly name: "hash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "ModuleControllerMismatch";
    readonly inputs: readonly [{
        readonly name: "moduleBit";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "expected";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "supplied";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ModuleIdentityMismatch";
    readonly inputs: readonly [{
        readonly name: "moduleBit";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ModuleSelectionMismatch";
    readonly inputs: readonly [{
        readonly name: "moduleBit";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyLauncher";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyProjectController";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ProjectAlreadyRegistered";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "SubjectAlreadyRegistered";
    readonly inputs: readonly [{
        readonly name: "subject";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "UnknownProject";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}];
export declare const projectVotesTokenAbi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "name_";
        readonly type: "string";
        readonly internalType: "string";
    }, {
        readonly name: "symbol_";
        readonly type: "string";
        readonly internalType: "string";
    }, {
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "creator_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "allocations_";
        readonly type: "tuple[]";
        readonly internalType: "struct ProjectVotesToken.TokenAllocation[]";
        readonly components: readonly [{
            readonly name: "recipient";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "amount";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }, {
        readonly name: "additionalVotingExclusions_";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "CLOCK_MODE";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "DOMAIN_SEPARATOR";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_ADDITIONAL_VOTING_EXCLUSIONS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "additionalVotingExclusions";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "allowance";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "spender";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "approve";
    readonly inputs: readonly [{
        readonly name: "spender";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "balanceOf";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "burn";
    readonly inputs: readonly [{
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "burnFrom";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "clock";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "creator";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "decimals";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "delegate";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "delegateBySig";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "delegates";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "eip712Domain";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "fields";
        readonly type: "bytes1";
        readonly internalType: "bytes1";
    }, {
        readonly name: "name";
        readonly type: "string";
        readonly internalType: "string";
    }, {
        readonly name: "version";
        readonly type: "string";
        readonly internalType: "string";
    }, {
        readonly name: "chainId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "verifyingContract";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "salt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "extensions";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "eligibleVotingSupply";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getPastTotalSupply";
    readonly inputs: readonly [{
        readonly name: "timepoint";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getPastVotes";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "timepoint";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getVotes";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "initialSupply";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isVotingExcluded";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "name";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "nonces";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "permit";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "spender";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "deadline";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "v";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "r";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "s";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "symbol";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalSupply";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "transfer";
    readonly inputs: readonly [{
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "transferFrom";
    readonly inputs: readonly [{
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "votingExclusionAt";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "votingExclusionCount";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "Approval";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "spender";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "DelegateChanged";
    readonly inputs: readonly [{
        readonly name: "delegator";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "fromDelegate";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "toDelegate";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "DelegateVotesChanged";
    readonly inputs: readonly [{
        readonly name: "delegate";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "previousVotes";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "newVotes";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "EIP712DomainChanged";
    readonly inputs: readonly [];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProjectVotesTokenCreated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "registry";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "creator";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "initialSupply";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "Transfer";
    readonly inputs: readonly [{
        readonly name: "from";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "VotingExclusionConfigured";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "automatic";
        readonly type: "bool";
        readonly indexed: false;
        readonly internalType: "bool";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "CheckpointUnorderedInsertion";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "DelegationUnsupported";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "DuplicateAllocation";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ECDSAInvalidSignature";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ECDSAInvalidSignatureLength";
    readonly inputs: readonly [{
        readonly name: "length";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ECDSAInvalidSignatureS";
    readonly inputs: readonly [{
        readonly name: "s";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC20InsufficientAllowance";
    readonly inputs: readonly [{
        readonly name: "spender";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "allowance";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "needed";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC20InsufficientBalance";
    readonly inputs: readonly [{
        readonly name: "sender";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "balance";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "needed";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC20InvalidApprover";
    readonly inputs: readonly [{
        readonly name: "approver";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC20InvalidReceiver";
    readonly inputs: readonly [{
        readonly name: "receiver";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC20InvalidSender";
    readonly inputs: readonly [{
        readonly name: "sender";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC20InvalidSpender";
    readonly inputs: readonly [{
        readonly name: "spender";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC2612ExpiredSignature";
    readonly inputs: readonly [{
        readonly name: "deadline";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC2612InvalidSigner";
    readonly inputs: readonly [{
        readonly name: "signer";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "FutureLookup";
    readonly inputs: readonly [{
        readonly name: "timepoint";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "currentClock";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAccountNonce";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "currentNonce";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAllocation";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAllocations";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidCreator";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidMetadata";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidShortString";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidVotingExclusion";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NoEligibleVotingSupply";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ReservedVotingExclusion";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "SafeCastOverflowedUintDowncast";
    readonly inputs: readonly [{
        readonly name: "bits";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "StringTooLong";
    readonly inputs: readonly [{
        readonly name: "str";
        readonly type: "string";
        readonly internalType: "string";
    }];
}, {
    readonly type: "error";
    readonly name: "TooManyVotingExclusions";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "UnsortedVotingExclusions";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "previous";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "current";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "VotesExpiredSignature";
    readonly inputs: readonly [{
        readonly name: "expiry";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}];
export declare const projectMultisigAccountV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "initialSigners";
        readonly type: "address[3]";
        readonly internalType: "address[3]";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "receive";
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "EXECUTION_THRESHOLD";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_ACTIONS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_TOTAL_CALLDATA";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "SIGNER_COUNT";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "TRANSACTION_TTL";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "actionAt";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "target";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "data";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "confirm";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "confirmationCount";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "count";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "confirmedBy";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "signer";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "confirmed";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "controller";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "execute";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "isExpired";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isReady";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isSigner";
    readonly inputs: readonly [{
        readonly name: "signer";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "active";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "nextNonce";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "onERC721Received";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "replaceSigner";
    readonly inputs: readonly [{
        readonly name: "oldSigner";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "newSigner";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "revokeConfirmation";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "signers";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address[3]";
        readonly internalType: "address[3]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "submit";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "calldatas";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }];
    readonly outputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "transactionActions";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "targets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "calldatas";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "transactionDetails";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct ProjectMultisigAccountV2.Transaction";
        readonly components: readonly [{
            readonly name: "nonce";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "actionsHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "submittedAt";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "expiresAt";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "actionCount";
            readonly type: "uint8";
            readonly internalType: "uint8";
        }, {
            readonly name: "executionConfirmationCount";
            readonly type: "uint8";
            readonly internalType: "uint8";
        }, {
            readonly name: "executed";
            readonly type: "bool";
            readonly internalType: "bool";
        }, {
            readonly name: "exists";
            readonly type: "bool";
            readonly internalType: "bool";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "ActionExecuted";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "target";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "returnDataHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ConfirmationRevoked";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "signer";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "MultisigAccountCreated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "account";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "signer0";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "signer1";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "signer2";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "NativeReceived";
    readonly inputs: readonly [{
        readonly name: "sender";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "SignerReplaced";
    readonly inputs: readonly [{
        readonly name: "oldSigner";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "newSigner";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "TransactionConfirmed";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "signer";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "TransactionExecuted";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "executor";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "TransactionSubmitted";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "nonce";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "submitter";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "expiresAt";
        readonly type: "uint64";
        readonly indexed: false;
        readonly internalType: "uint64";
    }, {
        readonly name: "actionsHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "AddressEmptyCode";
    readonly inputs: readonly [{
        readonly name: "target";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "AlreadyConfirmed";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "signer";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "CalldataLimitExceeded";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "maximum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "FailedCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InsufficientBalance";
    readonly inputs: readonly [{
        readonly name: "balance";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "needed";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidActionCount";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBatchLengths";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "values";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "calldatas";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidEOACall";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "target";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidReplacement";
    readonly inputs: readonly [{
        readonly name: "oldSigner";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "newSigner";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSigner";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTarget";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "target";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NotConfirmed";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "signer";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NotSelf";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NotSigner";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ProjectIdentityMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "actual";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "ReentrancyGuardReentrantCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "SafeCastOverflowedUintDowncast";
    readonly inputs: readonly [{
        readonly name: "bits";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "SignerReplacementAlreadyPerformed";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "ThresholdNotMet";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "confirmations";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "TransactionAlreadyExecuted";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "TransactionExpired";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "expiresAt";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
}, {
    readonly type: "error";
    readonly name: "UnknownTransaction";
    readonly inputs: readonly [{
        readonly name: "transactionId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "UnsortedSigners";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "previous";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "current";
        readonly type: "address";
        readonly internalType: "address";
    }];
}];
export declare const projectGovernorV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "voteSource_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "timelock_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "config";
        readonly type: "tuple";
        readonly internalType: "struct TokenGovernanceConfig";
        readonly components: readonly [{
            readonly name: "votingDelay";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "votingPeriod";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "proposalThresholdBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "quorumBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "timelockDelay";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "referenceSupply";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "receive";
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "BALLOT_TYPEHASH";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "CLOCK_MODE";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "COUNTING_MODE";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "EXTENDED_BALLOT_TYPEHASH";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_PROPOSAL_THRESHOLD_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_QUORUM_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_VOTING_DELAY";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_VOTING_PERIOD";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_PROPOSAL_THRESHOLD_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_QUORUM_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_VOTING_DELAY";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_VOTING_PERIOD";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "cancel";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "calldatas";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }, {
        readonly name: "descriptionHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "castVote";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "support";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "castVoteBySig";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "support";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "voter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "signature";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "castVoteWithReason";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "support";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "reason";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "castVoteWithReasonAndParams";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "support";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "reason";
        readonly type: "string";
        readonly internalType: "string";
    }, {
        readonly name: "params";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "castVoteWithReasonAndParamsBySig";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "support";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "voter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "reason";
        readonly type: "string";
        readonly internalType: "string";
    }, {
        readonly name: "params";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }, {
        readonly name: "signature";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "clock";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "controller";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "eip712Domain";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "fields";
        readonly type: "bytes1";
        readonly internalType: "bytes1";
    }, {
        readonly name: "name";
        readonly type: "string";
        readonly internalType: "string";
    }, {
        readonly name: "version";
        readonly type: "string";
        readonly internalType: "string";
    }, {
        readonly name: "chainId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "verifyingContract";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "salt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "extensions";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "execute";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "calldatas";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }, {
        readonly name: "descriptionHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "getProposalId";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "calldatas";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }, {
        readonly name: "descriptionHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getVotes";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "timepoint";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getVotesWithParams";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "timepoint";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "params";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "hasVoted";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "hashProposal";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "calldatas";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }, {
        readonly name: "descriptionHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "name";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "nonces";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "onERC1155BatchReceived";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "onERC1155Received";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "onERC721Received";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "proposalDeadline";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "proposalEta";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "proposalNeedsQueuing";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "proposalProposer";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "proposalSnapshot";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "proposalThreshold";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "proposalThresholdAmount";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "proposalThresholdBps";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "proposalVotes";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "againstVotes";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "forVotes";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "abstainVotes";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "propose";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "calldatas";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }, {
        readonly name: "description";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "queue";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "calldatas";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }, {
        readonly name: "descriptionHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "quorum";
    readonly inputs: readonly [{
        readonly name: "timepoint";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "quorumBps";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "referenceSupply";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "relay";
    readonly inputs: readonly [{
        readonly name: "target";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "data";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "stakedVoteSource";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "state";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "enum IGovernor.ProposalState";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "supportsInterface";
    readonly inputs: readonly [{
        readonly name: "interfaceId";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "timelock";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "token";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract IERC5805";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "updateTimelock";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract TimelockController";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "version";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "voteSource";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "votingDelay";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "votingDelaySeconds";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "votingPeriod";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "votingPeriodSeconds";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "EIP712DomainChanged";
    readonly inputs: readonly [];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProposalCanceled";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProposalCreated";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "proposer";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "targets";
        readonly type: "address[]";
        readonly indexed: false;
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly indexed: false;
        readonly internalType: "uint256[]";
    }, {
        readonly name: "signatures";
        readonly type: "string[]";
        readonly indexed: false;
        readonly internalType: "string[]";
    }, {
        readonly name: "calldatas";
        readonly type: "bytes[]";
        readonly indexed: false;
        readonly internalType: "bytes[]";
    }, {
        readonly name: "voteStart";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "voteEnd";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "description";
        readonly type: "string";
        readonly indexed: false;
        readonly internalType: "string";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProposalExecuted";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProposalQueued";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "etaSeconds";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "TimelockChange";
    readonly inputs: readonly [{
        readonly name: "oldTimelock";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "newTimelock";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "VoteCast";
    readonly inputs: readonly [{
        readonly name: "voter";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "support";
        readonly type: "uint8";
        readonly indexed: false;
        readonly internalType: "uint8";
    }, {
        readonly name: "weight";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "reason";
        readonly type: "string";
        readonly indexed: false;
        readonly internalType: "string";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "VoteCastWithParams";
    readonly inputs: readonly [{
        readonly name: "voter";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "support";
        readonly type: "uint8";
        readonly indexed: false;
        readonly internalType: "uint8";
    }, {
        readonly name: "weight";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "reason";
        readonly type: "string";
        readonly indexed: false;
        readonly internalType: "string";
    }, {
        readonly name: "params";
        readonly type: "bytes";
        readonly indexed: false;
        readonly internalType: "bytes";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "FailedCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "GovernorAlreadyCastVote";
    readonly inputs: readonly [{
        readonly name: "voter";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "GovernorAlreadyQueuedProposal";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "GovernorDisabledDeposit";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "GovernorInsufficientProposerVotes";
    readonly inputs: readonly [{
        readonly name: "proposer";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "votes";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "threshold";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "GovernorInvalidProposalLength";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "calldatas";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "values";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "GovernorInvalidSignature";
    readonly inputs: readonly [{
        readonly name: "voter";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "GovernorInvalidVoteParams";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "GovernorInvalidVoteType";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "GovernorInvalidVotingPeriod";
    readonly inputs: readonly [{
        readonly name: "votingPeriod";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "GovernorNonexistentProposal";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "GovernorNotQueuedProposal";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "GovernorOnlyExecutor";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "GovernorQueueNotImplemented";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "GovernorRestrictedProposer";
    readonly inputs: readonly [{
        readonly name: "proposer";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "GovernorUnableToCancel";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "GovernorUnexpectedProposalState";
    readonly inputs: readonly [{
        readonly name: "proposalId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "current";
        readonly type: "uint8";
        readonly internalType: "enum IGovernor.ProposalState";
    }, {
        readonly name: "expectedStates";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAccountNonce";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "currentNonce";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidProposalThresholdBps";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidQuorumBps";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidReferenceSupply";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidShortString";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTimelock";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "deployer";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidVoteSource";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidVotingDelay";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidVotingPeriod";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
}, {
    readonly type: "error";
    readonly name: "ProjectIdentityMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "actual";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "ReferenceSupplyMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "SafeCastOverflowedUintDowncast";
    readonly inputs: readonly [{
        readonly name: "bits";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "StakedVoteSourceSubjectMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "actual";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "StringTooLong";
    readonly inputs: readonly [{
        readonly name: "str";
        readonly type: "string";
        readonly internalType: "string";
    }];
}, {
    readonly type: "error";
    readonly name: "TimelockImmutable";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "UnsupportedClockMode";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "string";
        readonly internalType: "string";
    }];
}];
export declare const projectTimelockV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "voteSource_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "config";
        readonly type: "tuple";
        readonly internalType: "struct TokenGovernanceConfig";
        readonly components: readonly [{
            readonly name: "votingDelay";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "votingPeriod";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "proposalThresholdBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "quorumBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "timelockDelay";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "referenceSupply";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "receive";
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "CANCELLER_ROLE";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "DEFAULT_ADMIN_ROLE";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "EXECUTOR_ROLE";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_TIMELOCK_DELAY";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_TIMELOCK_DELAY";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PROPOSER_ROLE";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "cancel";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "controller";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "execute";
    readonly inputs: readonly [{
        readonly name: "target";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "payload";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }, {
        readonly name: "predecessor";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "salt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "executeBatch";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "payloads";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }, {
        readonly name: "predecessor";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "salt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "getMinDelay";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getOperationState";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "enum TimelockController.OperationState";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getRoleAdmin";
    readonly inputs: readonly [{
        readonly name: "role";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getTimestamp";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "governor";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract ProjectGovernorV2";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "grantRole";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "hasRole";
    readonly inputs: readonly [{
        readonly name: "role";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "hashOperation";
    readonly inputs: readonly [{
        readonly name: "target";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "data";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }, {
        readonly name: "predecessor";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "salt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "hashOperationBatch";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "payloads";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }, {
        readonly name: "predecessor";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "salt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "isOperation";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isOperationDone";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isOperationPending";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isOperationReady";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "onERC1155BatchReceived";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "onERC1155Received";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "onERC721Received";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "renounceRole";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "revokeRole";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "schedule";
    readonly inputs: readonly [{
        readonly name: "target";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "data";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }, {
        readonly name: "predecessor";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "salt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "delay";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "scheduleBatch";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "values";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "payloads";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }, {
        readonly name: "predecessor";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "salt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "delay";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "supportsInterface";
    readonly inputs: readonly [{
        readonly name: "interfaceId";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "updateDelay";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "voteSource";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "CallExecuted";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "target";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "data";
        readonly type: "bytes";
        readonly indexed: false;
        readonly internalType: "bytes";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "CallSalt";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "salt";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "CallScheduled";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "target";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "data";
        readonly type: "bytes";
        readonly indexed: false;
        readonly internalType: "bytes";
    }, {
        readonly name: "predecessor";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }, {
        readonly name: "delay";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "Cancelled";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "MinDelayChange";
    readonly inputs: readonly [{
        readonly name: "oldDuration";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "newDuration";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RoleAdminChanged";
    readonly inputs: readonly [{
        readonly name: "role";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "previousAdminRole";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "newAdminRole";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RoleGranted";
    readonly inputs: readonly [{
        readonly name: "role";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "account";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "sender";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RoleRevoked";
    readonly inputs: readonly [{
        readonly name: "role";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "account";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "sender";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "TokenGovernanceCreated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "governor";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "timelock";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "voteSource";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "AccessControlBadConfirmation";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "AccessControlUnauthorizedAccount";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "neededRole";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "FailedCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTimelockDelay";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "ProjectIdentityMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "actual";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "TimelockConfigurationImmutable";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "TimelockInsufficientDelay";
    readonly inputs: readonly [{
        readonly name: "delay";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "minDelay";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "TimelockInvalidOperationLength";
    readonly inputs: readonly [{
        readonly name: "targets";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "payloads";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "values";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "TimelockUnauthorizedCaller";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "TimelockUnexecutedPredecessor";
    readonly inputs: readonly [{
        readonly name: "predecessorId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "TimelockUnexpectedOperationState";
    readonly inputs: readonly [{
        readonly name: "operationId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "expectedStates";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}];
export declare const projectTreasuryVaultV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "creator_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "controller_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "integrationApprovalRoot_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "basketManager_";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "receive";
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_BASKET_ROUTE_ASSETS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_REDEMPTION_ASSETS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "NATIVE_ASSET";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "TREASURY_SWAP_APPROVAL_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "accountedBalance";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "availableBalance";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketAllocationBps";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketManager";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketRoute";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "enabled";
        readonly type: "bool";
        readonly internalType: "bool";
    }, {
        readonly name: "allocationBps";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }, {
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "configHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "activatedAt";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "assets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketRouteActivatedAt";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketRouteConfigHash";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketRouteEnabled";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketRouteStatus";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "enabled";
        readonly type: "bool";
        readonly internalType: "bool";
    }, {
        readonly name: "eligible";
        readonly type: "bool";
        readonly internalType: "bool";
    }, {
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "allocationBps";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }, {
        readonly name: "pendingAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "beginOwnedBasketBurn";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "configureBasketRoute";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "allocationBps";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }, {
        readonly name: "assets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }];
    readonly outputs: readonly [{
        readonly name: "configHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "controller";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "creator";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "deposit";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "routeToBasket";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "depositNative";
    readonly inputs: readonly [{
        readonly name: "routeToBasket";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "disableBasketRoute";
    readonly inputs: readonly [];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "executeBasketRoute";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "maxAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "finalizeOwnedBasketBurn";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "assets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "amounts";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "initializeBasketRouteFromLauncher";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "allocationBps";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }, {
        readonly name: "assets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }];
    readonly outputs: readonly [{
        readonly name: "configHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "integrationApprovalRoot";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isAssetBacked";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isBasketRouteAsset";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isOwnedBasketRegistered";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isSwapApproved";
    readonly inputs: readonly [{
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "priceGuard";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "assetIn";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "assetOut";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "routeHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "approvalProof";
        readonly type: "bytes32[]";
        readonly internalType: "bytes32[]";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "launchBasketRouteInitialized";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "measuredBalance";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "onERC721Received";
    readonly inputs: readonly [{
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "ownedBasketAt";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "ownedBasketCount";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "ownedBasketIds";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "reserveForBasket";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "reservedForBasket";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "routedBasketId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "send";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "swap";
    readonly inputs: readonly [{
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "priceGuard";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "assetIn";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "assetOut";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amountIn";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "callerMinOut";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "routeData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }, {
        readonly name: "guardData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }, {
        readonly name: "approvalProof";
        readonly type: "bytes32[]";
        readonly internalType: "bytes32[]";
    }];
    readonly outputs: readonly [{
        readonly name: "amountOut";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "swapApprovalLeaf";
    readonly inputs: readonly [{
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "priceGuard";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "assetIn";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "assetOut";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "routeHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "syncAndReserve";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "surplus";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "reserved";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "syncAsset";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "surplus";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "syncBasketNft";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "transferBasketNft";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "updateOwnedBasket";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "config";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "event";
    readonly name: "AssetReceived";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "sender";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "basketRequested";
        readonly type: "bool";
        readonly indexed: false;
        readonly internalType: "bool";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "AssetSent";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "AssetSynced";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "surplus";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketNftBurnStarted";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketNftBurned";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "subjectBurnPrice";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketNftConfigurationUpdated";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "configHash";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketNftReceived";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "from";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "operator";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketNftTransferred";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketRouteConfigured";
    readonly inputs: readonly [{
        readonly name: "configHash";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "allocationBps";
        readonly type: "uint16";
        readonly indexed: false;
        readonly internalType: "uint16";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketRouteDisabled";
    readonly inputs: readonly [{
        readonly name: "previousConfigHash";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketRouteExecuted";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketRouteReleased";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketRouteReserved";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "TreasurySwap";
    readonly inputs: readonly [{
        readonly name: "assetIn";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "assetOut";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amountIn";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "amountOut";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "routeHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "TreasuryVaultCreated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "controller";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "creator";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "integrationApprovalRoot";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }, {
        readonly name: "basketManager";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "AssetUnderbacked";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "accounted";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "BasketAlreadyRegistered";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "BasketNftStillExists";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "BasketNotOwned";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "BasketNotRegistered";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "BasketRedemptionMismatch";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "BasketRouteNotEnabled";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "BasketRoutingUnavailable";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "GuardQuoteExpired";
    readonly inputs: readonly [{
        readonly name: "validUntil";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "currentTime";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactAssetReceipt";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactAssetSpend";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactBasketFunding";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "reported";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InsufficientAvailableBalance";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "available";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "requested";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InsufficientSwapOutput";
    readonly inputs: readonly [{
        readonly name: "minimum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAmount";
    readonly inputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAsset";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBasketAllocation";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBasketManager";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBasketNft";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBasketProject";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "expected";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "actual";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBasketRouteAssets";
    readonly inputs: readonly [{
        readonly name: "count";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidController";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidCreator";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidGuardMinimum";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRecipient";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRedemptionAssets";
    readonly inputs: readonly [{
        readonly name: "count";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSwapIntegration";
    readonly inputs: readonly [{
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "priceGuard";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSwapPair";
    readonly inputs: readonly [{
        readonly name: "assetIn";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "assetOut";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "LaunchBasketRouteAlreadyInitialized";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "LaunchWindowClosed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "NativeTransferFailed";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NoBasketReservation";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyController";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyLauncher";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ProjectIdentityMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "actual";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "ReentrancyGuardReentrantCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "SafeCastOverflowedUintDowncast";
    readonly inputs: readonly [{
        readonly name: "bits";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "SafeERC20FailedOperation";
    readonly inputs: readonly [{
        readonly name: "token";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "SwapNotApproved";
    readonly inputs: readonly [{
        readonly name: "leaf";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "UnsortedBasketRouteAssets";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "previous";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "current";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "UnsortedRedemptionAssets";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "previous";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "current";
        readonly type: "address";
        readonly internalType: "address";
    }];
}];
export declare const projectRouterV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "creator_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "controller_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "protocolFeeRecipient_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "treasury_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "airdrop_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "raffle_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "liquidityManager_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "integrationApprovalRoot_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "initialRoutes";
        readonly type: "tuple[]";
        readonly internalType: "struct RouterRouteInput[]";
        readonly components: readonly [{
            readonly name: "inputAsset";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "actions";
            readonly type: "tuple[]";
            readonly internalType: "struct RouterAction[]";
            readonly components: readonly [{
                readonly name: "actionType";
                readonly type: "uint8";
                readonly internalType: "enum RouterActionType";
            }, {
                readonly name: "allocationBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "recipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "adapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "priceGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "actionConfig";
                readonly type: "bytes";
                readonly internalType: "bytes";
            }];
        }];
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "receive";
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_ACTIONS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_ACTION_CONFIG_BYTES";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_INITIAL_ROUTES";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_INITIAL_ROUTE_DATA_BYTES";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_TOTAL_CONFIG_BYTES";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "NATIVE_ASSET";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PAUSED_REASON_HASH";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PROTOCOL_FEE_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "SWAP_APPROVAL_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "actionPaused";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "paused";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "actionStatus";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "action";
        readonly type: "tuple";
        readonly internalType: "struct RouterAction";
        readonly components: readonly [{
            readonly name: "actionType";
            readonly type: "uint8";
            readonly internalType: "enum RouterActionType";
        }, {
            readonly name: "allocationBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "recipient";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "adapter";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "priceGuard";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "actionConfig";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }];
    }, {
        readonly name: "paused";
        readonly type: "bool";
        readonly internalType: "bool";
    }, {
        readonly name: "cumulativeAllocation";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "retryableEscrow";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "activateRoute";
    readonly inputs: readonly [{
        readonly name: "route";
        readonly type: "tuple";
        readonly internalType: "struct RouterRouteInput";
        readonly components: readonly [{
            readonly name: "inputAsset";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "actions";
            readonly type: "tuple[]";
            readonly internalType: "struct RouterAction[]";
            readonly components: readonly [{
                readonly name: "actionType";
                readonly type: "uint8";
                readonly internalType: "enum RouterActionType";
            }, {
                readonly name: "allocationBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "recipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "adapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "priceGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "actionConfig";
                readonly type: "bytes";
                readonly internalType: "bytes";
            }];
        }];
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "activeRoute";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "header";
        readonly type: "tuple";
        readonly internalType: "struct ProjectRouterV2.RouteHeader";
        readonly components: readonly [{
            readonly name: "version";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "activatedAt";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "actionCount";
            readonly type: "uint8";
            readonly internalType: "uint8";
        }, {
            readonly name: "routeHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "totalRouted";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "exists";
            readonly type: "bool";
            readonly internalType: "bool";
        }];
    }, {
        readonly name: "actions";
        readonly type: "tuple[]";
        readonly internalType: "struct RouterAction[]";
        readonly components: readonly [{
            readonly name: "actionType";
            readonly type: "uint8";
            readonly internalType: "enum RouterActionType";
        }, {
            readonly name: "allocationBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "recipient";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "adapter";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "priceGuard";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "actionConfig";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "activeRouteVersion";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "airdrop";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "allocatedToAction";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "controller";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "creator";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "escrowed";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "execute";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "maxAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "callerMinOuts";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }, {
        readonly name: "guardData";
        readonly type: "bytes[]";
        readonly internalType: "bytes[]";
    }];
    readonly outputs: readonly [{
        readonly name: "batchAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "executeAction";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "actionIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "callerMinOut";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "guardData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "assetOut";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amountOut";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "fund";
    readonly inputs: readonly [{
        readonly name: "projectId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "config";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "received";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "initializeRoutesFromLauncher";
    readonly inputs: readonly [{
        readonly name: "initialRoutes";
        readonly type: "tuple[]";
        readonly internalType: "struct RouterRouteInput[]";
        readonly components: readonly [{
            readonly name: "inputAsset";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "actions";
            readonly type: "tuple[]";
            readonly internalType: "struct RouterAction[]";
            readonly components: readonly [{
                readonly name: "actionType";
                readonly type: "uint8";
                readonly internalType: "enum RouterActionType";
            }, {
                readonly name: "allocationBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "recipient";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "adapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "priceGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "actionConfig";
                readonly type: "bytes";
                readonly internalType: "bytes";
            }];
        }];
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "integrationApprovalRoot";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isAssetBacked";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isSinkApproved";
    readonly inputs: readonly [{
        readonly name: "sink";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isSwapApproved";
    readonly inputs: readonly [{
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "priceGuard";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "assetIn";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "assetOut";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "routeHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "proof";
        readonly type: "bytes32[]";
        readonly internalType: "bytes32[]";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "launchRoutesInitialized";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "liquidityManager";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "pauseAction";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "actionIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "pending";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectedAllocations";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "protocolFeeRecipient";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "protocolFeeRemainder";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "remainder";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "protocolOwed";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "raffle";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "recoverEscrow";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "fromVersion";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "fromActionIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "maxAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "toActionIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "resumeAction";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "actionIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "retryEscrow";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "actionIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "maxAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "callerMinOut";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "guardData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "succeeded";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "routeAction";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct RouterAction";
        readonly components: readonly [{
            readonly name: "actionType";
            readonly type: "uint8";
            readonly internalType: "enum RouterActionType";
        }, {
            readonly name: "allocationBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "recipient";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "adapter";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "priceGuard";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "actionConfig";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "routeActions";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple[]";
        readonly internalType: "struct RouterAction[]";
        readonly components: readonly [{
            readonly name: "actionType";
            readonly type: "uint8";
            readonly internalType: "enum RouterActionType";
        }, {
            readonly name: "allocationBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "recipient";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "adapter";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "priceGuard";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "actionConfig";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "routeHeader";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct ProjectRouterV2.RouteHeader";
        readonly components: readonly [{
            readonly name: "version";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "activatedAt";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "actionCount";
            readonly type: "uint8";
            readonly internalType: "uint8";
        }, {
            readonly name: "routeHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "totalRouted";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "exists";
            readonly type: "bool";
            readonly internalType: "bool";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "sendProtocolFee";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "maxAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "swapApprovalLeaf";
    readonly inputs: readonly [{
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "priceGuard";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "assetIn";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "assetOut";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "routeHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "sync";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "surplus";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "net";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "totalEscrowed";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalLiability";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "treasury";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "workStatus";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "routeVersion";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "pendingAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "escrowAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "feeAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "ActionEscrowed";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "actionIndex";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "reasonHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ActionExecuted";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "actionIndex";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "amountIn";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "assetOut";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "amountOut";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "EscrowRecovered";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "fromVersion";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "fromActionIndex";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "toVersion";
        readonly type: "uint64";
        readonly indexed: false;
        readonly internalType: "uint64";
    }, {
        readonly name: "toActionIndex";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "EscrowRetried";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "actionIndex";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "succeeded";
        readonly type: "bool";
        readonly indexed: false;
        readonly internalType: "bool";
    }, {
        readonly name: "reasonHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "Funded";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "source";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "gross";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "protocolFee";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "net";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "attributed";
        readonly type: "bool";
        readonly indexed: false;
        readonly internalType: "bool";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProtocolFeeSent";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RawNativeReceived";
    readonly inputs: readonly [{
        readonly name: "sender";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RouteActivated";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "routeHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RoutePaused";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "actionIndex";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RouteResumed";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "actionIndex";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RouterCreated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "controller";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "creator";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "protocolFeeRecipient";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "integrationApprovalRoot";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "ActionAlreadyPaused";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ActionConfigTooLarge";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ActionIsPaused";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ActionNotPaused";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "AssetUnderbacked";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "liability";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "DestinationIdentityMismatch";
    readonly inputs: readonly [{
        readonly name: "destination";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "GuardQuoteExpired";
    readonly inputs: readonly [{
        readonly name: "validUntil";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "currentTime";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactAssetReceipt";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactAssetSpend";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactBurn";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactSinkFunding";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "reported";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InitialRouteDataTooLarge";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "maximum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InputArrayLengthMismatch";
    readonly inputs: readonly [{
        readonly name: "actions";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "minima";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "guardData";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InsufficientSwapOutput";
    readonly inputs: readonly [{
        readonly name: "minimum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "IntegrationNotApproved";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "leaf";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAction";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "actionType";
        readonly type: "uint8";
        readonly internalType: "enum RouterActionType";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidActionCount";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAllocation";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAllocationTotal";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAmount";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAsset";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidController";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidCreator";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidDestination";
    readonly inputs: readonly [{
        readonly name: "destination";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidFeeRecipient";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidFundingConfig";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidFundingIdentity";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidGuardMinimum";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidIntegration";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "priceGuard";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRecipient";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRecoveryTarget";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "LaunchRoutesAlreadyInitialized";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "LaunchWindowClosed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "NativeTransferFailed";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NativeValueMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NoActiveRoute";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NoEscrow";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NoPending";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NoProtocolFee";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NoSurplus";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyController";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyLauncher";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlySelf";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ProjectIdentityMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "actual";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "ReentrancyGuardReentrantCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "RouteAlreadyConfigured";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "SafeCastOverflowedUintDowncast";
    readonly inputs: readonly [{
        readonly name: "bits";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "SafeERC20FailedOperation";
    readonly inputs: readonly [{
        readonly name: "token";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "SinkNotRegistered";
    readonly inputs: readonly [{
        readonly name: "sink";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "TotalConfigTooLarge";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "UnknownRoute";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "version";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
}];
export declare const projectStakingPoolV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "treasury_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "controller_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "guardian_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "lockDuration_";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "CLOCK_MODE";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "MAX_LOCK_DURATION";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_LOCK_DURATION";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "activePositionCount";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "backingBalance";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "balanceOfStake";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "clock";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "controller";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "delegate";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "delegateBySig";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "delegates";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "getPastStake";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "timepoint";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getPastTotalStaked";
    readonly inputs: readonly [{
        readonly name: "timepoint";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getPastTotalSupply";
    readonly inputs: readonly [{
        readonly name: "timepoint";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getPastVotes";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "timepoint";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "getVotes";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "guardian";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isSolvent";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "lockDuration";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "newStakesPaused";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "nextTokenId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "onPositionTransfer";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "pauseNewStakes";
    readonly inputs: readonly [];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "posNFT";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract ProjectPoSNFT";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "positionData";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint128";
        readonly internalType: "uint128";
    }, {
        readonly name: "createdAt";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "unlockAt";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "recoverSurplus";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "resumeNewStakes";
    readonly inputs: readonly [];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "stake";
    readonly inputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract IERC20";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "surplusBalance";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalActiveStake";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "treasury";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "unstake";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "event";
    readonly name: "DelegateChanged";
    readonly inputs: readonly [{
        readonly name: "delegator";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "fromDelegate";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "toDelegate";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "DelegateVotesChanged";
    readonly inputs: readonly [{
        readonly name: "delegate";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "previousVotes";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "newVotes";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "NewStakesPaused";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "NewStakesResumed";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "PositionCreated";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "funder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "owner";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "unlockAt";
        readonly type: "uint64";
        readonly indexed: false;
        readonly internalType: "uint64";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "PositionRedeemed";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "owner";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "PositionTransferred";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "from";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "StakingPoolCreated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "posNFT";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "lockDuration";
        readonly type: "uint64";
        readonly indexed: false;
        readonly internalType: "uint64";
    }, {
        readonly name: "treasury";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "controller";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "guardian";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "SurplusRecovered";
    readonly inputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "treasury";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "CheckpointUnorderedInsertion";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "DelegationUnsupported";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "FutureLookup";
    readonly inputs: readonly [{
        readonly name: "timepoint";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "currentClock";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactTokenTransfer";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "actual";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidController";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidGuardian";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidLockDuration";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidPositionRecipient";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidPositionTransfer";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRedemptionRecipient";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidStakeAmount";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTreasury";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NoSurplus";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "NotPositionOperator";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyController";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyPoSNFT";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "PositionNotMature";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "unlockAt";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "currentTime";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
}, {
    readonly type: "error";
    readonly name: "ProjectIdentityMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "actual";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "ReentrancyGuardReentrantCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "SafeCastOverflowedUintDowncast";
    readonly inputs: readonly [{
        readonly name: "bits";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "SafeERC20FailedOperation";
    readonly inputs: readonly [{
        readonly name: "token";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "StakingNotPaused";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "StakingPaused";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "UnauthorizedPause";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "VotesExpiredSignature";
    readonly inputs: readonly [{
        readonly name: "expiry";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}];
export declare const projectPoSNftAbi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "pool_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "projectId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "approve";
    readonly inputs: readonly [{
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "balanceOf";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "burn";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "getApproved";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isApprovedForAll";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isApprovedOrOwner";
    readonly inputs: readonly [{
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "name";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "ownerOf";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "pool";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "safeMint";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "safeTransferFrom";
    readonly inputs: readonly [{
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "safeTransferFrom";
    readonly inputs: readonly [{
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "data";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "setApprovalForAll";
    readonly inputs: readonly [{
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "approved";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "supportsInterface";
    readonly inputs: readonly [{
        readonly name: "interfaceId";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "symbol";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "tokenURI";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "transferFrom";
    readonly inputs: readonly [{
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "event";
    readonly name: "Approval";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "approved";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ApprovalForAll";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "operator";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "approved";
        readonly type: "bool";
        readonly indexed: false;
        readonly internalType: "bool";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "Transfer";
    readonly inputs: readonly [{
        readonly name: "from";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "ERC721IncorrectOwner";
    readonly inputs: readonly [{
        readonly name: "sender";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InsufficientApproval";
    readonly inputs: readonly [{
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InvalidApprover";
    readonly inputs: readonly [{
        readonly name: "approver";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InvalidOperator";
    readonly inputs: readonly [{
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InvalidOwner";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InvalidReceiver";
    readonly inputs: readonly [{
        readonly name: "receiver";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InvalidSender";
    readonly inputs: readonly [{
        readonly name: "sender";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721NonexistentToken";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidPositionRecipient";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyPool";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "StringsInsufficientHexLength";
    readonly inputs: readonly [{
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "length";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}];
export declare const projectAirdropV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "creator_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "treasury_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "protocolFeeRecipient_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "attestor_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "eligibilitySource_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "eligibilityMode_";
        readonly type: "uint8";
        readonly internalType: "enum AirdropEligibilityMode";
    }, {
        readonly name: "additionalExclusions";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "ACCOUNT_CONFIG_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "ACCOUNT_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "COMMITMENT_TYPEHASH";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "LEAF_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_EXCLUSIONS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_PROOF_DEPTH";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_PUSH_BATCH_SIZE";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_SNAPSHOT_CONFIRMATIONS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "NATIVE_ASSET";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "NODE_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PAYMENT_GAS_LIMIT";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PONS_LOCKER";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PROTOCOL_FEE_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "accountCommittedUnpaid";
    readonly inputs: readonly [{
        readonly name: "accountId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "accountConfigHash";
    readonly inputs: readonly [{
        readonly name: "accountId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "config";
        readonly type: "tuple";
        readonly internalType: "struct AirdropAccountConfig";
        readonly components: readonly [{
            readonly name: "maxPushBatchSize";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "minimumSnapshotConfirmations";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "cadence";
            readonly type: "uint8";
            readonly internalType: "enum AirdropCadence";
        }, {
            readonly name: "dustDestination";
            readonly type: "uint8";
            readonly internalType: "enum AirdropDustDestination";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "accountId";
    readonly inputs: readonly [{
        readonly name: "funder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "accountStatus";
    readonly inputs: readonly [{
        readonly name: "accountId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "account";
        readonly type: "tuple";
        readonly internalType: "struct ProjectAirdropV2.AccountState";
        readonly components: readonly [{
            readonly name: "funder";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "asset";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "configHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "uncommittedFunding";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "committedUnpaid";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "lastEpochId";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "lastSnapshotBlock";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "lastSnapshotTime";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "feeRemainder";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "maxPushBatchSize";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "minimumSnapshotConfirmations";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "cadence";
            readonly type: "uint8";
            readonly internalType: "enum AirdropCadence";
        }, {
            readonly name: "dustDestination";
            readonly type: "uint8";
            readonly internalType: "enum AirdropDustDestination";
        }, {
            readonly name: "exists";
            readonly type: "bool";
            readonly internalType: "bool";
        }];
    }, {
        readonly name: "committedUnpaid";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "assetRetryableCredits";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "attestor";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "cadenceSeconds";
    readonly inputs: readonly [{
        readonly name: "cadence";
        readonly type: "uint8";
        readonly internalType: "enum AirdropCadence";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "commitEpoch";
    readonly inputs: readonly [{
        readonly name: "commitment";
        readonly type: "tuple";
        readonly internalType: "struct AirdropEpochCommitment";
        readonly components: readonly [{
            readonly name: "accountId";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "epochId";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "snapshotBlock";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "snapshotBlockHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "snapshotTime";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "rootHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "rootSum";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "epochAmount";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "totalEligibleWeight";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "leafCount";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "artifactHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }];
    }, {
        readonly name: "signature";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "commitmentDigest";
    readonly inputs: readonly [{
        readonly name: "commitment";
        readonly type: "tuple";
        readonly internalType: "struct AirdropEpochCommitment";
        readonly components: readonly [{
            readonly name: "accountId";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "epochId";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "snapshotBlock";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "snapshotBlockHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "snapshotTime";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "rootHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "rootSum";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "epochAmount";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "totalEligibleWeight";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "leafCount";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "artifactHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "creator";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "deliverPayment";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "domainSeparator";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "eligibilityAt";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "timepoint";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "eligibilityMode";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "enum AirdropEligibilityMode";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "eligibilitySource";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "epochStatus";
    readonly inputs: readonly [{
        readonly name: "accountId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct ProjectAirdropV2.EpochState";
        readonly components: readonly [{
            readonly name: "snapshotBlock";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "snapshotTime";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "leafCount";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "settledLeafCount";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "snapshotBlockHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "rootHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "artifactHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "rootSum";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "epochAmount";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "totalEligibleWeight";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "settledEntitlement";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "finalized";
            readonly type: "bool";
            readonly internalType: "bool";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "exclusionAt";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "exclusionCount";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "exclusionHash";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "exclusions";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "finalizeEpoch";
    readonly inputs: readonly [{
        readonly name: "accountId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "fund";
    readonly inputs: readonly [{
        readonly name: "projectId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "config";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "received";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "isAssetBacked";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isExcluded";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "leafHash";
    readonly inputs: readonly [{
        readonly name: "accountId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "snapshotBlock";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "snapshotTime";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "leaf";
        readonly type: "tuple";
        readonly internalType: "struct AirdropLeaf";
        readonly components: readonly [{
            readonly name: "holder";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "weight";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "amount";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "nodeHash";
    readonly inputs: readonly [{
        readonly name: "leftHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "leftWeightSum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "leftAmountSum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "leftLeafCount";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }, {
        readonly name: "rightHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "rightWeightSum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "rightAmountSum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "rightLeafCount";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "processed";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "done";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "protocolFeeRecipient";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "protocolOwed";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "push";
    readonly inputs: readonly [{
        readonly name: "accountId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "leaves";
        readonly type: "tuple[]";
        readonly internalType: "struct AirdropLeaf[]";
        readonly components: readonly [{
            readonly name: "holder";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "weight";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "amount";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }, {
        readonly name: "proofs";
        readonly type: "tuple[]";
        readonly internalType: "struct AirdropProof[]";
        readonly components: readonly [{
            readonly name: "nodes";
            readonly type: "tuple[]";
            readonly internalType: "struct AirdropProofNode[]";
            readonly components: readonly [{
                readonly name: "siblingHash";
                readonly type: "bytes32";
                readonly internalType: "bytes32";
            }, {
                readonly name: "siblingWeightSum";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "siblingAmountSum";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "siblingLeafCount";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "siblingOnLeft";
                readonly type: "bool";
                readonly internalType: "bool";
            }];
        }];
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "recoverSurplus";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "maxAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "retryCredit";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "maxAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "succeeded";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "retryableCredit";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "sendProtocolFee";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "maxAmount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "surplusBalance";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalCommittedUnpaid";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalEligibleWeightAt";
    readonly inputs: readonly [{
        readonly name: "timepoint";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly outputs: readonly [{
        readonly name: "eligible";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalLiability";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalRetryableCredits";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalUncommitted";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "treasury";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "verifyProof";
    readonly inputs: readonly [{
        readonly name: "accountId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "leaf";
        readonly type: "tuple";
        readonly internalType: "struct AirdropLeaf";
        readonly components: readonly [{
            readonly name: "holder";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "weight";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "amount";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }, {
        readonly name: "proof";
        readonly type: "tuple";
        readonly internalType: "struct AirdropProof";
        readonly components: readonly [{
            readonly name: "nodes";
            readonly type: "tuple[]";
            readonly internalType: "struct AirdropProofNode[]";
            readonly components: readonly [{
                readonly name: "siblingHash";
                readonly type: "bytes32";
                readonly internalType: "bytes32";
            }, {
                readonly name: "siblingWeightSum";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "siblingAmountSum";
                readonly type: "uint256";
                readonly internalType: "uint256";
            }, {
                readonly name: "siblingLeafCount";
                readonly type: "uint32";
                readonly internalType: "uint32";
            }, {
                readonly name: "siblingOnLeft";
                readonly type: "bool";
                readonly internalType: "bool";
            }];
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "AccountConfigured";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "funder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "eligibilityMode";
        readonly type: "uint8";
        readonly indexed: false;
        readonly internalType: "enum AirdropEligibilityMode";
    }, {
        readonly name: "configHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "AirdropCreated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "eligibilitySource";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "eligibilityMode";
        readonly type: "uint8";
        readonly indexed: false;
        readonly internalType: "enum AirdropEligibilityMode";
    }, {
        readonly name: "attestor";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "exclusionHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "CreditDelivered";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "CreditRetryFailed";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "reasonHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "DustDeferred";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "reasonHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "EpochCommitted";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "snapshotBlock";
        readonly type: "uint64";
        readonly indexed: false;
        readonly internalType: "uint64";
    }, {
        readonly name: "snapshotTime";
        readonly type: "uint48";
        readonly indexed: false;
        readonly internalType: "uint48";
    }, {
        readonly name: "rootHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }, {
        readonly name: "rootSum";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "epochAmount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "artifactHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "EpochFinalized";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "divisionDust";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "destination";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ExclusionConfigured";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "automatic";
        readonly type: "bool";
        readonly indexed: false;
        readonly internalType: "bool";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "Funded";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "gross";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "protocolFee";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "net";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "PaymentDeferred";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "holder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "reasonHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "PaymentSucceeded";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "holder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProtocolFeeSent";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "SurplusRecovered";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "AccountConfigMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "supplied";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "AssetUnderbacked";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "liability";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "CadenceNotElapsed";
    readonly inputs: readonly [{
        readonly name: "earliest";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "supplied";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "EligibleWeightMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "EmptyPushBatch";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "EpochAlreadyFinalized";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
}, {
    readonly type: "error";
    readonly name: "EpochNotSettled";
    readonly inputs: readonly [{
        readonly name: "settledLeaves";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }, {
        readonly name: "totalLeaves";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }, {
        readonly name: "settled";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "rootSum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ExcludedHolder";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "HolderAlreadyProcessed";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactAssetReceipt";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactAssetSpend";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InputArrayLengthMismatch";
    readonly inputs: readonly [{
        readonly name: "leaves";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "proofs";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InsufficientAccountFunding";
    readonly inputs: readonly [{
        readonly name: "available";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "requested";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAmount";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAsset";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAttestation";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidAttestor";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidCommitment";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidCreator";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidDustDestination";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint8";
        readonly internalType: "enum AirdropDustDestination";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidEligibilitySource";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidEntitlement";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidEpochId";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "supplied";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidExclusion";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidFeeRecipient";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidFunder";
    readonly inputs: readonly [{
        readonly name: "funder";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidFundingIdentity";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidHolderWeight";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidMerkleSumProof";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidPushBatchSize";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSnapshotBlock";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "currentBlock";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSnapshotConfirmations";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSnapshotTime";
    readonly inputs: readonly [{
        readonly name: "previous";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "supplied";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "currentTime";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTreasury";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "MissingAccountConfig";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "NativeTransferFailed";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NativeValueMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NoProtocolFee";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NoRetryableCredit";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NoSurplus";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NonCanonicalAccountConfig";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "OnlySelf";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ProjectIdentityMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "actual";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "ProofTooDeep";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "PushBatchTooLarge";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "maximum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ReentrancyGuardReentrantCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ReservedExclusion";
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "SafeERC20FailedOperation";
    readonly inputs: readonly [{
        readonly name: "token";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "SnapshotHashMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "supplied";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "SnapshotNotFinal";
    readonly inputs: readonly [{
        readonly name: "confirmations";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "required";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "SnapshotOutsideHashWindow";
    readonly inputs: readonly [{
        readonly name: "confirmations";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "StakedSourceSubjectMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "actual";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "TooManyExclusions";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "UnknownAccount";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "UnknownEpoch";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "epochId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
}, {
    readonly type: "error";
    readonly name: "UnsortedExclusions";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "previous";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "current";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "UnsupportedClockMode";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "string";
        readonly internalType: "string";
    }];
}];
export declare const basketManagerV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "creator_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "controller_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "treasury_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "router_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "airdrop_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "stakingPool_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "integrationApprovalRoot_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "basketVaultImplementation_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "config";
        readonly type: "tuple";
        readonly internalType: "struct BasketConfig";
        readonly components: readonly [{
            readonly name: "cadence";
            readonly type: "uint8";
            readonly internalType: "enum BasketHarvestCadence";
        }, {
            readonly name: "eligibilityMode";
            readonly type: "uint8";
            readonly internalType: "enum BasketEligibilityMode";
        }, {
            readonly name: "governanceUpdatesEnabled";
            readonly type: "bool";
            readonly internalType: "bool";
        }, {
            readonly name: "burnTaxBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "burnTaxDestination";
            readonly type: "uint8";
            readonly internalType: "enum BasketBurnTaxDestination";
        }, {
            readonly name: "burnPriceSubject";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "airdropAccountConfig";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }, {
            readonly name: "allocation";
            readonly type: "tuple";
            readonly internalType: "struct BasketAllocationConfig";
            readonly components: readonly [{
                readonly name: "inputAssets";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }, {
                readonly name: "targets";
                readonly type: "tuple[]";
                readonly internalType: "struct BasketTarget[]";
                readonly components: readonly [{
                    readonly name: "depositAsset";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "yieldAdapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "targetWeightBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "rewardAssets";
                    readonly type: "address[]";
                    readonly internalType: "address[]";
                }, {
                    readonly name: "yieldApprovalProof";
                    readonly type: "bytes32[]";
                    readonly internalType: "bytes32[]";
                }];
            }, {
                readonly name: "swapLegs";
                readonly type: "tuple[]";
                readonly internalType: "struct BasketSwapLeg[]";
                readonly components: readonly [{
                    readonly name: "inputAsset";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "targetIndex";
                    readonly type: "uint8";
                    readonly internalType: "uint8";
                }, {
                    readonly name: "swapAdapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "priceGuard";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "maxSlippageBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "routeData";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }, {
                    readonly name: "approvalProof";
                    readonly type: "bytes32[]";
                    readonly internalType: "bytes32[]";
                }];
            }];
        }];
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_BURN_TAX_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PRIMARY_BASKET_ID";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "airdrop";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketMetadata";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "vault";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "state_";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "cadence_";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "burnPrice";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "taxBps";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketNFT";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract IERC721";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketProjectId";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketVaultImplementation";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "beginBurn";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "burnPriceSubject";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "burnTaxBps";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "burnTaxDestination";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "enum BasketBurnTaxDestination";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "cadence";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "enum BasketHarvestCadence";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "controller";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "creator";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "currentConfigurationHash";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "eligibilityMode";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "enum BasketEligibilityMode";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "finalizeBurn";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "assets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "amounts";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "finalizePrimaryBasket";
    readonly inputs: readonly [];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "fund";
    readonly inputs: readonly [{
        readonly name: "projectId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "config";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "received";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "governanceUpdatesEnabled";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "harvest";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "initialConfigurationHash";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "integrationApprovalRoot";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isBasketTransferAllowed";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "primaryBasketFinalized";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "primaryVault";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract BasketVaultV2";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "processBurnTarget";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "redemptionAssets";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "assets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "retryPendingDividend";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "funded";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "router";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "stakingPool";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "state";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "enum BasketState";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "treasury";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "updateConfiguration";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "config";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "event";
    readonly name: "BasketBurnBegun";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "owner";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketBurnFinalized";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "owner";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "subjectBurnPrice";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "assets";
        readonly type: "address[]";
        readonly indexed: false;
        readonly internalType: "address[]";
    }, {
        readonly name: "ownerAmounts";
        readonly type: "uint256[]";
        readonly indexed: false;
        readonly internalType: "uint256[]";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketBurnTargetProcessed";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketConfigurationUpdated";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "previousConfigurationHash";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "newConfigurationHash";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketDividendRetried";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "funded";
        readonly type: "bool";
        readonly indexed: false;
        readonly internalType: "bool";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketFunded";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "funder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketHarvested";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "nextHarvestAt";
        readonly type: "uint48";
        readonly indexed: false;
        readonly internalType: "uint48";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "PrimaryBasketReady";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "treasury";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "vault";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "configurationHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "AirdropCadenceMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint8";
        readonly internalType: "enum AirdropCadence";
    }, {
        readonly name: "actual";
        readonly type: "uint8";
        readonly internalType: "enum AirdropCadence";
    }];
}, {
    readonly type: "error";
    readonly name: "BurnTargetsIncomplete";
    readonly inputs: readonly [{
        readonly name: "processed";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "total";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "EligibilityModeMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "actual";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
}, {
    readonly type: "error";
    readonly name: "EligibilitySourceMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "actual";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "FailedDeployment";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "GovernanceUpdatesDisabled";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InexactAssetReceipt";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactAssetSpend";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactSubjectBurn";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactVaultFunding";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "reported";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InsufficientBalance";
    readonly inputs: readonly [{
        readonly name: "balance";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "needed";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAmount";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidApprovalRoot";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidBasketId";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBurnTax";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBurnTaxDestination";
    readonly inputs: readonly [{
        readonly name: "destination";
        readonly type: "uint8";
        readonly internalType: "enum BasketBurnTaxDestination";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidController";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidCreator";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidFundingConfig";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidFundingIdentity";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidModule";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidState";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint8";
        readonly internalType: "enum BasketState";
    }, {
        readonly name: "actual";
        readonly type: "uint8";
        readonly internalType: "enum BasketState";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTreasury";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NativeValueMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NotBasketOwner";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "PrimaryBasketAlreadyFinalized";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "PrimaryBasketNotFinalized";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ProjectIdentityMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "actual";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "ReentrancyGuardReentrantCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "SafeERC20FailedOperation";
    readonly inputs: readonly [{
        readonly name: "token";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "StakingRequired";
    readonly inputs: readonly [];
}];
export declare const basketVaultV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "receive";
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_INPUT_ASSETS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_REWARD_ASSETS_PER_TARGET";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_TARGETS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_TRACKED_ASSETS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "NATIVE_ASSET";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "SWAP_APPROVAL_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "YIELD_APPROVAL_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "activate";
    readonly inputs: readonly [];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "activated";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "airdrop";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "airdropAccountConfig";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "allocateFunding";
    readonly inputs: readonly [{
        readonly name: "inputAsset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "received";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "allocated";
    readonly inputs: readonly [{
        readonly name: "inputAsset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "basketId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "beginBurn";
    readonly inputs: readonly [];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "burnBegun";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "burnTaxBps";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "burnTaxDestination";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "enum BasketBurnTaxDestination";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "cadence";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "enum BasketHarvestCadence";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "closed";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "configurationValidated";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "creator";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "eligibilityMode";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "enum BasketEligibilityMode";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "finalizeRedemption";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "assets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "ownerAmounts";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "fundPendingDividend";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "harvest";
    readonly inputs: readonly [];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "initialConfigurationHash";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "initialize";
    readonly inputs: readonly [{
        readonly name: "manager_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "projectId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "basketId_";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "creator_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "treasury_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "router_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "airdrop_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "integrationApprovalRoot_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "config";
        readonly type: "tuple";
        readonly internalType: "struct BasketConfig";
        readonly components: readonly [{
            readonly name: "cadence";
            readonly type: "uint8";
            readonly internalType: "enum BasketHarvestCadence";
        }, {
            readonly name: "eligibilityMode";
            readonly type: "uint8";
            readonly internalType: "enum BasketEligibilityMode";
        }, {
            readonly name: "governanceUpdatesEnabled";
            readonly type: "bool";
            readonly internalType: "bool";
        }, {
            readonly name: "burnTaxBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "burnTaxDestination";
            readonly type: "uint8";
            readonly internalType: "enum BasketBurnTaxDestination";
        }, {
            readonly name: "burnPriceSubject";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "airdropAccountConfig";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }, {
            readonly name: "allocation";
            readonly type: "tuple";
            readonly internalType: "struct BasketAllocationConfig";
            readonly components: readonly [{
                readonly name: "inputAssets";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }, {
                readonly name: "targets";
                readonly type: "tuple[]";
                readonly internalType: "struct BasketTarget[]";
                readonly components: readonly [{
                    readonly name: "depositAsset";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "yieldAdapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "targetWeightBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "rewardAssets";
                    readonly type: "address[]";
                    readonly internalType: "address[]";
                }, {
                    readonly name: "yieldApprovalProof";
                    readonly type: "bytes32[]";
                    readonly internalType: "bytes32[]";
                }];
            }, {
                readonly name: "swapLegs";
                readonly type: "tuple[]";
                readonly internalType: "struct BasketSwapLeg[]";
                readonly components: readonly [{
                    readonly name: "inputAsset";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "targetIndex";
                    readonly type: "uint8";
                    readonly internalType: "uint8";
                }, {
                    readonly name: "swapAdapter";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "priceGuard";
                    readonly type: "address";
                    readonly internalType: "address";
                }, {
                    readonly name: "maxSlippageBps";
                    readonly type: "uint16";
                    readonly internalType: "uint16";
                }, {
                    readonly name: "routeData";
                    readonly type: "bytes";
                    readonly internalType: "bytes";
                }, {
                    readonly name: "approvalProof";
                    readonly type: "bytes32[]";
                    readonly internalType: "bytes32[]";
                }];
            }];
        }];
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "inputAssets";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "integrationApprovalRoot";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "lastHarvestAt";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "manager";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "nextHarvestAt";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "pendingDividend";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "pendingDividendAssetCount";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "processBurnTarget";
    readonly inputs: readonly [{
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "processedBurnTargets";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "retryPendingDividend";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "funded";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "router";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "swapApprovalLeaf";
    readonly inputs: readonly [{
        readonly name: "inputAsset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "priceGuard";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "maxSlippageBps";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }, {
        readonly name: "routeHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "targetCount";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "targetStatus";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "depositAsset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "yieldAdapter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "targetWeightBps";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }, {
        readonly name: "lockedPrincipal";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "positionValue";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "unrealizedGain";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "unrealizedLoss";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "burnProcessed";
        readonly type: "bool";
        readonly internalType: "bool";
    }, {
        readonly name: "rewardAssets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalFunded";
    readonly inputs: readonly [{
        readonly name: "inputAsset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "total";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "trackedAssets";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "treasury";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "updateAllocation";
    readonly inputs: readonly [{
        readonly name: "allocation";
        readonly type: "tuple";
        readonly internalType: "struct BasketAllocationConfig";
        readonly components: readonly [{
            readonly name: "inputAssets";
            readonly type: "address[]";
            readonly internalType: "address[]";
        }, {
            readonly name: "targets";
            readonly type: "tuple[]";
            readonly internalType: "struct BasketTarget[]";
            readonly components: readonly [{
                readonly name: "depositAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "yieldAdapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "targetWeightBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "rewardAssets";
                readonly type: "address[]";
                readonly internalType: "address[]";
            }, {
                readonly name: "yieldApprovalProof";
                readonly type: "bytes32[]";
                readonly internalType: "bytes32[]";
            }];
        }, {
            readonly name: "swapLegs";
            readonly type: "tuple[]";
            readonly internalType: "struct BasketSwapLeg[]";
            readonly components: readonly [{
                readonly name: "inputAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "targetIndex";
                readonly type: "uint8";
                readonly internalType: "uint8";
            }, {
                readonly name: "swapAdapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "priceGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "maxSlippageBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "routeData";
                readonly type: "bytes";
                readonly internalType: "bytes";
            }, {
                readonly name: "approvalProof";
                readonly type: "bytes32[]";
                readonly internalType: "bytes32[]";
            }];
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "configurationHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "validateConfiguration";
    readonly inputs: readonly [];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "yieldApprovalLeaf";
    readonly inputs: readonly [{
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "depositAsset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "AllocationConfigurationUpdated";
    readonly inputs: readonly [{
        readonly name: "configurationHash";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BasketActivated";
    readonly inputs: readonly [{
        readonly name: "activatedAt";
        readonly type: "uint48";
        readonly indexed: true;
        readonly internalType: "uint48";
    }, {
        readonly name: "firstHarvestAt";
        readonly type: "uint48";
        readonly indexed: true;
        readonly internalType: "uint48";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BurnStarted";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BurnTargetProcessed";
    readonly inputs: readonly [{
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "adapter";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ConfigurationValidated";
    readonly inputs: readonly [{
        readonly name: "configurationHash";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "DividendFunded";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "DividendPending";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "reasonHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "FundingAllocated";
    readonly inputs: readonly [{
        readonly name: "inputAsset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "depositAsset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "inputAmount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "depositedAmount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "HarvestCompleted";
    readonly inputs: readonly [{
        readonly name: "harvestedAt";
        readonly type: "uint48";
        readonly indexed: true;
        readonly internalType: "uint48";
    }, {
        readonly name: "nextHarvestAt";
        readonly type: "uint48";
        readonly indexed: true;
        readonly internalType: "uint48";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "AdapterOutputMismatch";
    readonly inputs: readonly [{
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "AlreadyActivated";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "AlreadyInitialized";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "BurnInProgress";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "BurnNotBegun";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "BurnTargetAlreadyProcessed";
    readonly inputs: readonly [{
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "BurnTargetsIncomplete";
    readonly inputs: readonly [{
        readonly name: "processed";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "total";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ConfigurationAlreadyValidated";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ConfigurationNotValidated";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "DuplicateSwapLeg";
    readonly inputs: readonly [{
        readonly name: "inputAsset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "GuardQuoteExpired";
    readonly inputs: readonly [{
        readonly name: "validUntil";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "currentTime";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "HarvestNotDue";
    readonly inputs: readonly [{
        readonly name: "earliest";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "currentTime";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactAssetReceipt";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactAssetSpend";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactYieldDeposit";
    readonly inputs: readonly [{
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InsufficientSwapOutput";
    readonly inputs: readonly [{
        readonly name: "minimum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "IntegrationNotApproved";
    readonly inputs: readonly [{
        readonly name: "leaf";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAirdropReceipt";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "reported";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAmount";
    readonly inputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAsset";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidFundingIdentity";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidGuardMinimum";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidInputCount";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidPositionUnits";
    readonly inputs: readonly [{
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRewardAssets";
    readonly inputs: readonly [{
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSwapLeg";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTarget";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTargetCount";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTargetWeights";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "MissingSwapLeg";
    readonly inputs: readonly [{
        readonly name: "inputAsset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NativeTransferFailed";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NativeValueMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NoPendingDividend";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyManager";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlySelf";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "PendingDividendsExist";
    readonly inputs: readonly [{
        readonly name: "assetCount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "PrincipalNotRestored";
    readonly inputs: readonly [{
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "principal";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "positionValue";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ReentrancyGuardReentrantCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "SafeCastOverflowedUintDowncast";
    readonly inputs: readonly [{
        readonly name: "bits";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "SafeERC20FailedOperation";
    readonly inputs: readonly [{
        readonly name: "token";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "TooManyTrackedAssets";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "UnsortedAddresses";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "previous";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "current";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "YieldAdapterBindingMismatch";
    readonly inputs: readonly [{
        readonly name: "targetIndex";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }];
}];
export declare const basketNftV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "manager_";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "approve";
    readonly inputs: readonly [{
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "balanceOf";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "burn";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "getApproved";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isApprovedForAll";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "manager";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "name";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "ownerOf";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "safeMint";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "safeTransferFrom";
    readonly inputs: readonly [{
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "safeTransferFrom";
    readonly inputs: readonly [{
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "data";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "setApprovalForAll";
    readonly inputs: readonly [{
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "approved";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "supportsInterface";
    readonly inputs: readonly [{
        readonly name: "interfaceId";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "symbol";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "tokenURI";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
        readonly internalType: "string";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "transferFrom";
    readonly inputs: readonly [{
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "event";
    readonly name: "Approval";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "approved";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ApprovalForAll";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "operator";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "approved";
        readonly type: "bool";
        readonly indexed: false;
        readonly internalType: "bool";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "Transfer";
    readonly inputs: readonly [{
        readonly name: "from";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "to";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "BasketTransferLocked";
    readonly inputs: readonly [{
        readonly name: "basketId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721IncorrectOwner";
    readonly inputs: readonly [{
        readonly name: "sender";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InsufficientApproval";
    readonly inputs: readonly [{
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InvalidApprover";
    readonly inputs: readonly [{
        readonly name: "approver";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InvalidOperator";
    readonly inputs: readonly [{
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InvalidOwner";
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InvalidReceiver";
    readonly inputs: readonly [{
        readonly name: "receiver";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721InvalidSender";
    readonly inputs: readonly [{
        readonly name: "sender";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ERC721NonexistentToken";
    readonly inputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBasketRecipient";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyManager";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "StringsInsufficientHexLength";
    readonly inputs: readonly [{
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "length";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}];
export declare const projectFundingBandsV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "encodedConfig";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "BAND_INTEGRATION_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BAND_SWAP_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_CONFIRMATION_PERIOD";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_DESTINATION_CONFIG_BYTES";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_LIVE_BANDS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_CONFIRMATION_PERIOD";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_TWAP_WINDOW";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "NATIVE_ASSET";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PROTOCOL_FEE_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "airdrop";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "armSettlement";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "observationData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "bandPositionStatus";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "state";
        readonly type: "uint8";
        readonly internalType: "enum FundingBandState";
    }, {
        readonly name: "positionId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "committedSubject";
        readonly type: "uint128";
        readonly internalType: "uint128";
    }, {
        readonly name: "liquidity";
        readonly type: "uint128";
        readonly internalType: "uint128";
    }, {
        readonly name: "subjectResidual";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "bandState";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "enum FundingBandState";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "bandStatus";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "value";
        readonly type: "tuple";
        readonly internalType: "struct ProjectFundingBandsV2.Band";
        readonly components: readonly [{
            readonly name: "lowerMarketCapUsdE8";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "upperMarketCapUsdE8";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "committedSubject";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "liquidity";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "positionId";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "subjectResidual";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "effectiveLowerTick";
            readonly type: "int24";
            readonly internalType: "int24";
        }, {
            readonly name: "effectiveUpperTick";
            readonly type: "int24";
            readonly internalType: "int24";
        }, {
            readonly name: "armedAt";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "armedObservationAt";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "armedObservationId";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "destinationConfigHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "destination";
            readonly type: "uint8";
            readonly internalType: "enum FundingBandDestination";
        }, {
            readonly name: "state";
            readonly type: "uint8";
            readonly internalType: "enum FundingBandState";
        }];
    }, {
        readonly name: "config";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "canonicalPool";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "confirmationPeriod";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "controller";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "createBand";
    readonly inputs: readonly [{
        readonly name: "config";
        readonly type: "tuple";
        readonly internalType: "struct FundingBandConfig";
        readonly components: readonly [{
            readonly name: "lowerMarketCapUsdE8";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "upperMarketCapUsdE8";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "subjectAmount";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "destination";
            readonly type: "uint8";
            readonly internalType: "enum FundingBandDestination";
        }, {
            readonly name: "destinationConfig";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }];
    }, {
        readonly name: "observationData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "creator";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "deliverBand";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "deliveryOwed";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "disarmSettlement";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "observationData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "feeRemainder";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "increaseBand";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "subjectAmount";
        readonly type: "uint128";
        readonly internalType: "uint128";
    }, {
        readonly name: "observationData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "integrationApprovalLeaf";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "integrationApprovalRoot";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isSwapApproved";
    readonly inputs: readonly [{
        readonly name: "swapConfig";
        readonly type: "tuple";
        readonly internalType: "struct FundingBandSwapConfig";
        readonly components: readonly [{
            readonly name: "swapAdapter";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "priceGuard";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "maxSlippageBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "routeData";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }, {
            readonly name: "guardData";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }, {
            readonly name: "approvalProof";
            readonly type: "bytes32[]";
            readonly internalType: "bytes32[]";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "liveBandCount";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "liveBandIds";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "marketCapGuard";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract IFundingBandMarketCapGuard";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "maximumObservationAge";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "nextBandId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "onERC721Received";
    readonly inputs: readonly [{
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "positionAdapter";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract IFundingBandPositionAdapter";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "positionManager";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "protocolFeeRecipient";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "protocolOwed";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "quoteAsset";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "raffle";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "recoverDelivery";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "newDestination";
        readonly type: "uint8";
        readonly internalType: "enum FundingBandDestination";
    }, {
        readonly name: "newDestinationConfig";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "delivered";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "recoverSurplus";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "maximum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "referenceSupply";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "reservedSubjectResidual";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "retryDelivery";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "delivered";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "router";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "sendProtocolFee";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "maximum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "settle";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "observationData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "surplusBalance";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "swapApprovalLeaf";
    readonly inputs: readonly [{
        readonly name: "swapConfig";
        readonly type: "tuple";
        readonly internalType: "struct FundingBandSwapConfig";
        readonly components: readonly [{
            readonly name: "swapAdapter";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "priceGuard";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "maxSlippageBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "routeData";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }, {
            readonly name: "guardData";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }, {
            readonly name: "approvalProof";
            readonly type: "bytes32[]";
            readonly internalType: "bytes32[]";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalDeliveryOwed";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "treasury";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "uncommittedSubjectBalance";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "BandArmed";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "qualifyingSince";
        readonly type: "uint48";
        readonly indexed: false;
        readonly internalType: "uint48";
    }, {
        readonly name: "executableAt";
        readonly type: "uint48";
        readonly indexed: false;
        readonly internalType: "uint48";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BandCreated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "bandId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "lowerMarketCapUsdE8";
        readonly type: "uint128";
        readonly indexed: false;
        readonly internalType: "uint128";
    }, {
        readonly name: "upperMarketCapUsdE8";
        readonly type: "uint128";
        readonly indexed: false;
        readonly internalType: "uint128";
    }, {
        readonly name: "subjectAmount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "destination";
        readonly type: "uint8";
        readonly indexed: false;
        readonly internalType: "enum FundingBandDestination";
    }, {
        readonly name: "destinationConfigHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BandDeliveryEscrowed";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BandDeliveryFailed";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "reasonHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BandDeliveryRecovered";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "previousDestination";
        readonly type: "uint8";
        readonly indexed: false;
        readonly internalType: "enum FundingBandDestination";
    }, {
        readonly name: "newDestination";
        readonly type: "uint8";
        readonly indexed: false;
        readonly internalType: "enum FundingBandDestination";
    }, {
        readonly name: "newConfigHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BandDeliverySucceeded";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BandDisarmed";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "observedMarketCapUsdE8";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BandFunded";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "subjectAmount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "positionId";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "liquidityAdded";
        readonly type: "uint128";
        readonly indexed: false;
        readonly internalType: "uint128";
    }, {
        readonly name: "subjectResidual";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "BandSettled";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "grossQuote";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "protocolFee";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "netQuote";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "subjectResidual";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "FundingBandsCreated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "controller";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "creator";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "treasury";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "canonicalPool";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "quoteAsset";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "referenceSupply";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "marketCapGuard";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "positionAdapter";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "confirmationPeriod";
        readonly type: "uint48";
        readonly indexed: false;
        readonly internalType: "uint48";
    }, {
        readonly name: "maximumObservationAge";
        readonly type: "uint48";
        readonly indexed: false;
        readonly internalType: "uint48";
    }, {
        readonly name: "integrationApprovalRoot";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProtocolFeeSent";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "SurplusRecovered";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "AdapterOutputMismatch";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ConfirmationNotElapsed";
    readonly inputs: readonly [{
        readonly name: "executableAt";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "currentTime";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "GuardQuoteExpired";
    readonly inputs: readonly [{
        readonly name: "validUntil";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "currentTime";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactAssetReceipt";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactAssetSpend";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactSubjectBurn";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InsufficientSwapOutput";
    readonly inputs: readonly [{
        readonly name: "minimum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "measured";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InsufficientUncommittedSubject";
    readonly inputs: readonly [{
        readonly name: "available";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "required";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "IntegrationNotApproved";
    readonly inputs: readonly [{
        readonly name: "leaf";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBand";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBandAmount";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBandBounds";
    readonly inputs: readonly [{
        readonly name: "lower";
        readonly type: "uint128";
        readonly internalType: "uint128";
    }, {
        readonly name: "upper";
        readonly type: "uint128";
        readonly internalType: "uint128";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidBandState";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "expected";
        readonly type: "uint8";
        readonly internalType: "enum FundingBandState";
    }, {
        readonly name: "actual";
        readonly type: "uint8";
        readonly internalType: "enum FundingBandState";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidCanonicalPool";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidConfirmationPeriod";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidController";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidCreator";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidDestination";
    readonly inputs: readonly [{
        readonly name: "destination";
        readonly type: "uint8";
        readonly internalType: "enum FundingBandDestination";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidDestinationConfig";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidEffectiveTicks";
    readonly inputs: readonly [{
        readonly name: "lower";
        readonly type: "int24";
        readonly internalType: "int24";
    }, {
        readonly name: "upper";
        readonly type: "int24";
        readonly internalType: "int24";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidFeeRecipient";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidFundingReceipt";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "reported";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidGuardMinimum";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidIntegration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidModule";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidObservation";
    readonly inputs: readonly [{
        readonly name: "observedAt";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "observationId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidObservationAge";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidPositionResult";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidReferenceSupply";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidTwapWindow";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }, {
        readonly name: "required";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "MarketCapNotAboveBand";
    readonly inputs: readonly [{
        readonly name: "observed";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "upper";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "MarketCapNotBelowBand";
    readonly inputs: readonly [{
        readonly name: "observed";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "lower";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NativeTransferFailed";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NoDeliveryOwed";
    readonly inputs: readonly [{
        readonly name: "bandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "NoProtocolFee";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "NoSurplus";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ObservationNotAdvanced";
    readonly inputs: readonly [{
        readonly name: "armedAt";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "observedAt";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyController";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlySelf";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OverlappingBand";
    readonly inputs: readonly [{
        readonly name: "existingBandId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "PositionMintMismatch";
    readonly inputs: readonly [{
        readonly name: "reported";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "received";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "PositionNotClosed";
    readonly inputs: readonly [{
        readonly name: "positionId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ReentrancyGuardReentrantCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "SafeCastOverflowedUintDowncast";
    readonly inputs: readonly [{
        readonly name: "bits";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "value";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "SafeERC20FailedOperation";
    readonly inputs: readonly [{
        readonly name: "token";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "TooManyLiveBands";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "UnexpectedPositionNft";
    readonly inputs: readonly [{
        readonly name: "nft";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "operator";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "from";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}];
export declare const projectRaffleV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "receive";
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "ARBSYS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "EMPTY_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "LEAF_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_CLAIM_WINDOW";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_EXCLUSIONS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_PAYOUT_TAX_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_PENDING_ROUNDS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_PROOF_LENGTH";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_RANDOMNESS_TIMEOUT";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_ROUND_INTERVAL";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_ROUTE_DATA_LENGTH";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_STOCK_REWARDS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_WEIGHT_WINDOW_BLOCKS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_WINNERS_PER_ROUND";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_CLAIM_WINDOW";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_RANDOMNESS_TIMEOUT";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_ROUND_INTERVAL";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "NODE_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PROTOCOL_FEE_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "SLOT_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "STOCK_DOMAIN";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "STOCK_FALLBACK_DIVISOR";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "abandonRound";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly outputs: readonly [{
        readonly name: "returned";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "availablePool";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "claim";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "slot";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "leaf";
        readonly type: "tuple";
        readonly internalType: "struct RaffleTypes.Leaf";
        readonly components: readonly [{
            readonly name: "holder";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tickets";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }, {
        readonly name: "proof";
        readonly type: "tuple[]";
        readonly internalType: "struct RaffleTypes.ProofElement[]";
        readonly components: readonly [{
            readonly name: "siblingHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "siblingSum";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "siblingIsLeft";
            readonly type: "bool";
            readonly internalType: "bool";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "paid";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "claimFunding";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "slot";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }, {
        readonly name: "leaf";
        readonly type: "tuple";
        readonly internalType: "struct RaffleTypes.Leaf";
        readonly components: readonly [{
            readonly name: "holder";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tickets";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }, {
        readonly name: "proof";
        readonly type: "tuple[]";
        readonly internalType: "struct RaffleTypes.ProofElement[]";
        readonly components: readonly [{
            readonly name: "siblingHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "siblingSum";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "siblingIsLeft";
            readonly type: "bool";
            readonly internalType: "bool";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "paid";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "commitRound";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "snapshotBlock";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "snapshotBlockHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "rootHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "totalTickets";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "prize";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "configHash";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "configuration";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct RaffleTypes.Settings";
        readonly components: readonly [{
            readonly name: "creator";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "attestor";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "randomness";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "prizeAsset";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "protocolFeeRecipient";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "taxRecipient";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tokensPerTicket";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "maxTicketsPerHolder";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "minPrize";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "maxPrize";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "prizeBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "recipientTaxBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "recycleTaxBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "minConfirmations";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "winnersPerRound";
            readonly type: "uint8";
            readonly internalType: "uint8";
        }, {
            readonly name: "minRoundInterval";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "weightWindowBlocks";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "randomnessTimeout";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "claimWindow";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "basis";
            readonly type: "uint8";
            readonly internalType: "enum RaffleTypes.TicketBasis";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "deliverOwed";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "deliverStockOwed";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "emptyLeafHash";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "expireRound";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly outputs: readonly [{
        readonly name: "returned";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "feeRemainder";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "fund";
    readonly inputs: readonly [{
        readonly name: "projectId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "configData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "received";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "fundingFallbackAt";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "initialize";
    readonly inputs: readonly [{
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "config";
        readonly type: "tuple";
        readonly internalType: "struct RaffleTypes.Config";
        readonly components: readonly [{
            readonly name: "creator";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "attestor";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "randomness";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "prizeAsset";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "protocolFeeRecipient";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "taxRecipient";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tokensPerTicket";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "maxTicketsPerHolder";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "minPrize";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "maxPrize";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "prizeBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "recipientTaxBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "recycleTaxBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "minConfirmations";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "winnersPerRound";
            readonly type: "uint8";
            readonly internalType: "uint8";
        }, {
            readonly name: "minRoundInterval";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "weightWindowBlocks";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "randomnessTimeout";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "claimWindow";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "basis";
            readonly type: "uint8";
            readonly internalType: "enum RaffleTypes.TicketBasis";
        }, {
            readonly name: "exclusions";
            readonly type: "address[]";
            readonly internalType: "address[]";
        }, {
            readonly name: "stockRewards";
            readonly type: "tuple[]";
            readonly internalType: "struct RaffleTypes.StockReward[]";
            readonly components: readonly [{
                readonly name: "asset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "swapAdapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "priceGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "routeData";
                readonly type: "bytes";
                readonly internalType: "bytes";
            }, {
                readonly name: "guardData";
                readonly type: "bytes";
                readonly internalType: "bytes";
            }];
        }];
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "initialized";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "isExcluded";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "excluded";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "lastCommitAt";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "latestRoundId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "latestSnapshotBlock";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "leafHash";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "snapshotBlock";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tickets";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "liabilities";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "nextPrize";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "nodeHash";
    readonly inputs: readonly [{
        readonly name: "leftHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "leftSum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "rightHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "rightSum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "owed";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "payStockWinner";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "payWinner";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "payoutTaxBps";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "pendingRounds";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "protocolOwed";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "receiveRandomness";
    readonly inputs: readonly [{
        readonly name: "requestId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "seed";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "roundOfRequest";
    readonly inputs: readonly [{
        readonly name: "requestId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "roundStatus";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct RaffleTypes.Round";
        readonly components: readonly [{
            readonly name: "rootHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "requestId";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "totalTickets";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "prize";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "paidTotal";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "seed";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "snapshotBlock";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "committedAt";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "drawnAt";
            readonly type: "uint64";
            readonly internalType: "uint64";
        }, {
            readonly name: "slotsPaidMask";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "state";
            readonly type: "uint8";
            readonly internalType: "enum RaffleTypes.RoundState";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "rounds";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }];
    readonly outputs: readonly [{
        readonly name: "rootHash";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "requestId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "totalTickets";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "prize";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "paidTotal";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "seed";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "snapshotBlock";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "committedAt";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "drawnAt";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "slotsPaidMask";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }, {
        readonly name: "state";
        readonly type: "uint8";
        readonly internalType: "enum RaffleTypes.RoundState";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "selectedStock";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "slot";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
    readonly outputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "sendProtocolFee";
    readonly inputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "sendTax";
    readonly inputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "slotPrize";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "slot";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "stockOwed";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "stockReward";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct RaffleTypes.StockReward";
        readonly components: readonly [{
            readonly name: "asset";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "swapAdapter";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "priceGuard";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "routeData";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }, {
            readonly name: "guardData";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "stockRewardCount";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "sync";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "credited";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "fee";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "taxOwed";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "ticketsFor";
    readonly inputs: readonly [{
        readonly name: "weight";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "tickets";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalIntake";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalOwed";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalReserved";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalStockOwed";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "verify";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "leaf";
        readonly type: "tuple";
        readonly internalType: "struct RaffleTypes.Leaf";
        readonly components: readonly [{
            readonly name: "holder";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tickets";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }];
    }, {
        readonly name: "proof";
        readonly type: "tuple[]";
        readonly internalType: "struct RaffleTypes.ProofElement[]";
        readonly components: readonly [{
            readonly name: "siblingHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "siblingSum";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "siblingIsLeft";
            readonly type: "bool";
            readonly internalType: "bool";
        }];
    }];
    readonly outputs: readonly [{
        readonly name: "valid";
        readonly type: "bool";
        readonly internalType: "bool";
    }, {
        readonly name: "offset";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "winningIndex";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly internalType: "uint64";
    }, {
        readonly name: "slot";
        readonly type: "uint8";
        readonly internalType: "uint8";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "Deposited";
    readonly inputs: readonly [{
        readonly name: "source";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "gross";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "fee";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "net";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "attributed";
        readonly type: "bool";
        readonly indexed: false;
        readonly internalType: "bool";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "OwedDelivered";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "caller";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "PaymentDeferred";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "slot";
        readonly type: "uint8";
        readonly indexed: true;
        readonly internalType: "uint8";
    }, {
        readonly name: "holder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "gross";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "recipientTax";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "recycleTax";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "net";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "reason";
        readonly type: "bytes";
        readonly indexed: false;
        readonly internalType: "bytes";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "PrizePaid";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "slot";
        readonly type: "uint8";
        readonly indexed: true;
        readonly internalType: "uint8";
    }, {
        readonly name: "holder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "gross";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "recipientTax";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "recycleTax";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "net";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProtocolFeeSent";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "caller";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RaffleCreated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "registry";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "configHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }, {
        readonly name: "configuration";
        readonly type: "tuple";
        readonly indexed: false;
        readonly internalType: "struct RaffleTypes.Settings";
        readonly components: readonly [{
            readonly name: "creator";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "attestor";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "randomness";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "prizeAsset";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "protocolFeeRecipient";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "taxRecipient";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "tokensPerTicket";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "maxTicketsPerHolder";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "minPrize";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "maxPrize";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "prizeBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "recipientTaxBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "recycleTaxBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "minConfirmations";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "winnersPerRound";
            readonly type: "uint8";
            readonly internalType: "uint8";
        }, {
            readonly name: "minRoundInterval";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "weightWindowBlocks";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "randomnessTimeout";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "claimWindow";
            readonly type: "uint32";
            readonly internalType: "uint32";
        }, {
            readonly name: "basis";
            readonly type: "uint8";
            readonly internalType: "enum RaffleTypes.TicketBasis";
        }];
    }, {
        readonly name: "exclusions";
        readonly type: "address[]";
        readonly indexed: false;
        readonly internalType: "address[]";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RandomnessReceived";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "requestId";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }, {
        readonly name: "seed";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RoundAbandoned";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "returned";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RoundCommitted";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "snapshotBlock";
        readonly type: "uint64";
        readonly indexed: false;
        readonly internalType: "uint64";
    }, {
        readonly name: "snapshotBlockHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }, {
        readonly name: "rootHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }, {
        readonly name: "totalTickets";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "prize";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "winnersPerRound";
        readonly type: "uint8";
        readonly indexed: false;
        readonly internalType: "uint8";
    }, {
        readonly name: "requestId";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "RoundExpired";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "returned";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "StockOwedDelivered";
    readonly inputs: readonly [{
        readonly name: "holder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "caller";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "StockPaymentDeferred";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "slot";
        readonly type: "uint8";
        readonly indexed: true;
        readonly internalType: "uint8";
    }, {
        readonly name: "holder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "gross";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "recipientTax";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "recycleTax";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "fundingSpent";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "payoutAsset";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "payoutAmount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "reason";
        readonly type: "bytes";
        readonly indexed: false;
        readonly internalType: "bytes";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "StockPrizePaid";
    readonly inputs: readonly [{
        readonly name: "roundId";
        readonly type: "uint64";
        readonly indexed: true;
        readonly internalType: "uint64";
    }, {
        readonly name: "slot";
        readonly type: "uint8";
        readonly indexed: true;
        readonly internalType: "uint8";
    }, {
        readonly name: "holder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "gross";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "recipientTax";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "recycleTax";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "fundingSpent";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "payoutAsset";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "payoutAmount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "StockRewardConfigured";
    readonly inputs: readonly [{
        readonly name: "index";
        readonly type: "uint8";
        readonly indexed: true;
        readonly internalType: "uint8";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "swapAdapter";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "priceGuard";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "routeData";
        readonly type: "bytes";
        readonly indexed: false;
        readonly internalType: "bytes";
    }, {
        readonly name: "guardData";
        readonly type: "bytes";
        readonly indexed: false;
        readonly internalType: "bytes";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "TaxSent";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "caller";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "AlreadyInitialized";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ApprovalFailed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "BalanceQueryFailed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ClaimWindowClosed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ClaimWindowOpen";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ConfigurationMismatch";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ExcludedHolder";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "FallbackUnavailable";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "Insolvent";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InsufficientOutput";
    readonly inputs: readonly [{
        readonly name: "minimum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "actual";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAddress";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidAmount";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidFundingIdentity";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidProof";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRequest";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidRoot";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidRound";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidSeed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidSlot";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidSnapshot";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidValue";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvariantViolation";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "NativeTransferFailed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "NonCanonicalConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "NotInitialized";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "NotWinningLeaf";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "NothingOwed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "OnlySelf";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "PrizeBelowFloor";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "QuoteExpired";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "RandomnessPending";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "Reentrancy";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "RoundTooSoon";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "SlotAlreadyPaid";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "SubjectNotBound";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "TooManyPendingRounds";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "TransferFailed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "TransferFromFailed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "Unauthorized";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "UnexpectedBalanceDelta";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "actual";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}];
export declare const projectLiquidityManagerV2Abi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "registry_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "v3Factory_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "v3PositionManager_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "v4PositionManager_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "v4StateView_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "permit2_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "protocolFeeRecipient_";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "receive";
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "BURN_ADDRESS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "DEADLINE_WINDOW";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_DYNAMIC_BYTES";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_MINT_SLIPPAGE_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MAX_QUOTE_SWAP_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "MIN_QUOTE_SWAP_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PROTOCOL_FEE_BPS";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "accountConfig";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct ProjectLiquidityManagerV2.Config";
        readonly components: readonly [{
            readonly name: "venue";
            readonly type: "uint8";
            readonly internalType: "enum ProjectLiquidityManagerV2.Venue";
        }, {
            readonly name: "quoteAsset";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "poolFee";
            readonly type: "uint24";
            readonly internalType: "uint24";
        }, {
            readonly name: "tickSpacing";
            readonly type: "int24";
            readonly internalType: "int24";
        }, {
            readonly name: "hooks";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "swapAdapter";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "priceGuard";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "swapRouteData";
            readonly type: "bytes";
            readonly internalType: "bytes";
        }, {
            readonly name: "quoteSwapBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "maxMintSlippageBps";
            readonly type: "uint16";
            readonly internalType: "uint16";
        }, {
            readonly name: "minNotionalPerMint";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "maxNotionalPerMint";
            readonly type: "uint128";
            readonly internalType: "uint128";
        }, {
            readonly name: "minMintInterval";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "feeMode";
            readonly type: "uint8";
            readonly internalType: "enum ProjectLiquidityManagerV2.FeeMode";
        }, {
            readonly name: "feeRecipient";
            readonly type: "address";
            readonly internalType: "address";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "accountFinancials";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "pendingQuote";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "pendingSubject";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "positionId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "lastMintAt";
        readonly type: "uint48";
        readonly internalType: "uint48";
    }, {
        readonly name: "configured";
        readonly type: "bool";
        readonly internalType: "bool";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "accountId";
    readonly inputs: readonly [{
        readonly name: "funder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "accountStatus";
    readonly inputs: readonly [{
        readonly name: "id";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "tuple";
        readonly internalType: "struct ProjectLiquidityManagerV2.Account";
        readonly components: readonly [{
            readonly name: "funder";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "subject";
            readonly type: "address";
            readonly internalType: "address";
        }, {
            readonly name: "config";
            readonly type: "tuple";
            readonly internalType: "struct ProjectLiquidityManagerV2.Config";
            readonly components: readonly [{
                readonly name: "venue";
                readonly type: "uint8";
                readonly internalType: "enum ProjectLiquidityManagerV2.Venue";
            }, {
                readonly name: "quoteAsset";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "poolFee";
                readonly type: "uint24";
                readonly internalType: "uint24";
            }, {
                readonly name: "tickSpacing";
                readonly type: "int24";
                readonly internalType: "int24";
            }, {
                readonly name: "hooks";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "swapAdapter";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "priceGuard";
                readonly type: "address";
                readonly internalType: "address";
            }, {
                readonly name: "swapRouteData";
                readonly type: "bytes";
                readonly internalType: "bytes";
            }, {
                readonly name: "quoteSwapBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "maxMintSlippageBps";
                readonly type: "uint16";
                readonly internalType: "uint16";
            }, {
                readonly name: "minNotionalPerMint";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "maxNotionalPerMint";
                readonly type: "uint128";
                readonly internalType: "uint128";
            }, {
                readonly name: "minMintInterval";
                readonly type: "uint48";
                readonly internalType: "uint48";
            }, {
                readonly name: "feeMode";
                readonly type: "uint8";
                readonly internalType: "enum ProjectLiquidityManagerV2.FeeMode";
            }, {
                readonly name: "feeRecipient";
                readonly type: "address";
                readonly internalType: "address";
            }];
        }, {
            readonly name: "configHash";
            readonly type: "bytes32";
            readonly internalType: "bytes32";
        }, {
            readonly name: "pendingQuote";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "pendingSubject";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "positionId";
            readonly type: "uint256";
            readonly internalType: "uint256";
        }, {
            readonly name: "lastMintAt";
            readonly type: "uint48";
            readonly internalType: "uint48";
        }, {
            readonly name: "configured";
            readonly type: "bool";
            readonly internalType: "bool";
        }];
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "collect";
    readonly inputs: readonly [{
        readonly name: "funder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "feeOwed";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "fund";
    readonly inputs: readonly [{
        readonly name: "projectId_";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "configData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "received";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "payable";
}, {
    readonly type: "function";
    readonly name: "mint";
    readonly inputs: readonly [{
        readonly name: "funder";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "subject_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "notional";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "callerMinOut";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "guardData";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "liquidity";
        readonly type: "uint128";
        readonly internalType: "uint128";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "onERC721Received";
    readonly inputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "tokenId";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "";
        readonly type: "bytes";
        readonly internalType: "bytes";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes4";
        readonly internalType: "bytes4";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "permit2";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract IAllowanceTransfer";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectAccountId";
    readonly inputs: readonly [{
        readonly name: "funder";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "projectId";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "protocolFeeRecipient";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "protocolFeeRemainder";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "remainder";
        readonly type: "uint16";
        readonly internalType: "uint16";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "protocolOwed";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "registry";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "sendFee";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "sendProtocolFee";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "subject";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalLiability";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "v3Factory";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract IUniswapV3Factory";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "v3PositionManager";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract INonfungiblePositionManager";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "v4PositionManager";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract IPositionManager";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "v4StateView";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract IV4StateView";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "AccountConfigured";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "funder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "quoteAsset";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }, {
        readonly name: "venue";
        readonly type: "uint8";
        readonly indexed: false;
        readonly internalType: "enum ProjectLiquidityManagerV2.Venue";
    }, {
        readonly name: "configHash";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "FeeSent";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "FeesCollected";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "amountQuote";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "amountSubject";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "mode";
        readonly type: "uint8";
        readonly indexed: false;
        readonly internalType: "enum ProjectLiquidityManagerV2.FeeMode";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "Funded";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "funder";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "quoteAsset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "pendingQuote";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "LiquidityManagerCreated";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "registry";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "protocolFeeRecipient";
        readonly type: "address";
        readonly indexed: false;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "PositionIncreased";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "positionId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "liquidity";
        readonly type: "uint128";
        readonly indexed: false;
        readonly internalType: "uint128";
    }, {
        readonly name: "amount0";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "amount1";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "PositionMinted";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "positionId";
        readonly type: "uint256";
        readonly indexed: true;
        readonly internalType: "uint256";
    }, {
        readonly name: "liquidity";
        readonly type: "uint128";
        readonly indexed: false;
        readonly internalType: "uint128";
    }, {
        readonly name: "amount0";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "amount1";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProtocolFeeAccrued";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "gross";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "fee";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "ProtocolFeeSent";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "recipient";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "caller";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "Swapped";
    readonly inputs: readonly [{
        readonly name: "accountId";
        readonly type: "bytes32";
        readonly indexed: true;
        readonly internalType: "bytes32";
    }, {
        readonly name: "quoteSpent";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "subjectReceived";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "enforcedMinimum";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "AccountNotFound";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ApproveFailed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "BalanceQueryFailed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "ConfigurationMismatch";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "Insolvent";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InsufficientCredit";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InsufficientOutput";
    readonly inputs: readonly [{
        readonly name: "minimum";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "actual";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAddress";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidAmount";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidExpiry";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidFundingIdentity";
    readonly inputs: readonly [{
        readonly name: "projectId";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }, {
        readonly name: "subject";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidInterval";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidMinimumOutput";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidPosition";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvalidRegistry";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidSubject";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidValue";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "InvariantViolation";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "NativeTransferFailed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "NonCanonicalConfiguration";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "PoolNotInitialized";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "Reentrancy";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "TransferFailed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "TransferFromFailed";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "UnexpectedBalanceDelta";
    readonly inputs: readonly [{
        readonly name: "asset";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "actual";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "UnexpectedNFT";
    readonly inputs: readonly [];
}];
export declare const erc4626BasketYieldAdapterAbi: readonly [{
    readonly type: "constructor";
    readonly inputs: readonly [{
        readonly name: "basketVault_";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "vault_";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "basketVault";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "deposit";
    readonly inputs: readonly [{
        readonly name: "assets";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly outputs: readonly [{
        readonly name: "positionUnits";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "depositAsset";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "exitAll";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "assets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "amounts";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "harvest";
    readonly inputs: readonly [{
        readonly name: "recipient";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly outputs: readonly [{
        readonly name: "assets";
        readonly type: "address[]";
        readonly internalType: "address[]";
    }, {
        readonly name: "amounts";
        readonly type: "uint256[]";
        readonly internalType: "uint256[]";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "managedPrincipal";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "totalAssets";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "assets";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "vault";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "contract IERC4626";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "Deposited";
    readonly inputs: readonly [{
        readonly name: "assets";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "shares";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "managedPrincipal";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "Exited";
    readonly inputs: readonly [{
        readonly name: "assets";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "event";
    readonly name: "Harvested";
    readonly inputs: readonly [{
        readonly name: "assets";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }, {
        readonly name: "remainingPositionValue";
        readonly type: "uint256";
        readonly indexed: false;
        readonly internalType: "uint256";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "InexactAssetMovement";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "actual";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InexactShareMovement";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "actual";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAddress";
    readonly inputs: readonly [{
        readonly name: "candidate";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidAmount";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "InvalidRecipient";
    readonly inputs: readonly [{
        readonly name: "supplied";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "OnlyBasketVault";
    readonly inputs: readonly [{
        readonly name: "caller";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "PrincipalImpaired";
    readonly inputs: readonly [{
        readonly name: "principal";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }, {
        readonly name: "positionValue";
        readonly type: "uint256";
        readonly internalType: "uint256";
    }];
}, {
    readonly type: "error";
    readonly name: "ReentrancyGuardReentrantCall";
    readonly inputs: readonly [];
}, {
    readonly type: "error";
    readonly name: "SafeERC20FailedOperation";
    readonly inputs: readonly [{
        readonly name: "token";
        readonly type: "address";
        readonly internalType: "address";
    }];
}];
export declare const erc4626BasketYieldAdapterFactoryAbi: readonly [{
    readonly type: "function";
    readonly name: "ADAPTER_RUNTIME_HASH";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "PROTOCOL_VERSION";
    readonly inputs: readonly [];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint32";
        readonly internalType: "uint32";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "function";
    readonly name: "adapterSalt";
    readonly inputs: readonly [{
        readonly name: "basketVault";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "erc4626Vault";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "userSalt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly stateMutability: "pure";
}, {
    readonly type: "function";
    readonly name: "deploy";
    readonly inputs: readonly [{
        readonly name: "basketVault";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "erc4626Vault";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "userSalt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "nonpayable";
}, {
    readonly type: "function";
    readonly name: "predict";
    readonly inputs: readonly [{
        readonly name: "basketVault";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "erc4626Vault";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "userSalt";
        readonly type: "bytes32";
        readonly internalType: "bytes32";
    }];
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
        readonly internalType: "address";
    }];
    readonly stateMutability: "view";
}, {
    readonly type: "event";
    readonly name: "AdapterDeployed";
    readonly inputs: readonly [{
        readonly name: "basketVault";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "erc4626Vault";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "adapter";
        readonly type: "address";
        readonly indexed: true;
        readonly internalType: "address";
    }, {
        readonly name: "userSalt";
        readonly type: "bytes32";
        readonly indexed: false;
        readonly internalType: "bytes32";
    }];
    readonly anonymous: false;
}, {
    readonly type: "error";
    readonly name: "DeploymentAddressMismatch";
    readonly inputs: readonly [{
        readonly name: "expected";
        readonly type: "address";
        readonly internalType: "address";
    }, {
        readonly name: "deployed";
        readonly type: "address";
        readonly internalType: "address";
    }];
}, {
    readonly type: "error";
    readonly name: "ExistingAdapterMismatch";
    readonly inputs: readonly [{
        readonly name: "adapter";
        readonly type: "address";
        readonly internalType: "address";
    }];
}];
//# sourceMappingURL=abis.generated.d.ts.map