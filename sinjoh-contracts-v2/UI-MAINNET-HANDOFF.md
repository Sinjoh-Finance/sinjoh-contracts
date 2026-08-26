# Sinjoh Project V2 mainnet UI handoff

Status: **canonical deployed release; use this release for production consumers**

- Chain: Robinhood Chain mainnet (`4663`)
- Release: `project-v2-public-pons-dual-funding-letscash-20260826-c184fad`
- Source commit: `c184faddd881ddcabdc26c70364f825b79a142d0`
- Active promotion SHA-256: `85a37923cd7a4d0ad3d83667686ee752d184fe3570332c74878bffc441c963b7`
- Deployment manifest SHA-256: `5be4748d0dc575ec14030e619a7da7ffc735bb63369a107aef7ea6d80ea30b2c`
- Active promotion run: `32929898024`

The signed promotion and `mainnet-deployments.json` are authoritative. Render consumer
configuration from them; do not copy an earlier generation into application source.

## Current Project contracts

| Contract | Address | Runtime code hash |
| --- | --- | --- |
| `ProjectLauncherV2` | `0x6b5e99b344C0671f77BAC00c5ADbE453Ffa39100` | `0x5dd89482f663119e13acfdbb0b3b89d35814f494cd8c90c0c3337f176395c824` |
| `ProjectRegistryV2` | `0xF2F0C38dd9E4DCBa46A4b8bE2E7441377c103Bf4` | `0x0638ed852649bdca466c3d3a231893176f0d2659aba56782387f58af9bcc31d2` |
| `ProjectLaunchDeployerV2` | `0xF2844Cd17F45adA05894AF938a96CB4417158f3B` | `0x53e0c3f1091041295157454414bf76becbc7225af1c9f883978a190152872c55` |
| `ProjectLaunchValidatorV2` | `0xA227633Cc64FeB8c36c63602cd3480e26c0F26Eb` | `0x943fc6a6f784346ae310d5376510ed8086b16d74eb3f4de5e3584bb53af7e7ed` |
| Pons adapter factory | `0xa16389c14c9299A4317D50aEfd5e4cC442F2dF0d` | `0x42b9b3eca3f4bf37072bcf60f3405e30bd6e95e7279c307cdef9c5905f67f3bf` |
| Project Pons adapter implementation | `0xC5C7B33708121d542AC8172104D1d708DF61cA37` | `0x305007652acf94952e5feb97add75c50ed8934365c67b3f1522eaf4809810841` |

Atomic public-Pons Project launches transact with the predicted adapter clone from
`0xa16389c14c9299A4317D50aEfd5e4cC442F2dF0d`. Direct Project-token launches transact with
`0x6b5e99b344C0671f77BAC00c5ADbE453Ffa39100`.

## Current public Pons dependencies

| Contract | Address | Runtime code hash |
| --- | --- | --- |
| Launch factory | `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e` | `0x89a27da6f703e0a7cdd4f233e7cb57604ff75b164530962d3ff7cf8483a67d84` |
| Launch deployer | `0x3711ceA4feaDE896C913C68F01Eda97Cb06D1A42` | `0xeade22566c766377f6adfb99534f2772251efad9568642c0704a7051418e624c` |
| Fee escrow | `0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e` | `0xf25f75cfbc1637ba068dc34f69098fa4e8a80f8ee8fe7bf7820594e0b3fed2f1` |
| Meme hook | `0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044` | `0xc21b1e6c1b45403e81a581f22ed6d9c747997af1cfdac1b1dc9f4b1d346a10db` |
| Buyback vault | `0x42df2a798f82289E177311362e8f5ccC45c1219c` | `0x5de8480874faffefa539648f1a7d6c1e69b39da3fa34de22fc95eb7586aece03` |
| Launch locker | `0x267444D099b10fB5Ed7c3Cc7B7c767AdcA574952` | `0x58455f80b3773871d601a025e56ec27c71ab3bbb8e2ca6b17828954450742025` |

## Current Funding Bands contracts

| Contract | Address | Runtime code hash |
| --- | --- | --- |
| Manager | `0x8AEb669200bcc03454Fe3B73124A4318027862e9` | `0x27e79a76b510ea9ba4018822199e31339c8ac4a083e2723d6ec0b305c168e3d6` |
| Launch verifier | `0x9d93036656C51dd9Fe2164f9325FeF850fC282D9` | `0xedb1114f6c470682c3142a35300db3bb0000cc42b73f2adbb3cdd554bb14d34d` |
| Launch escrow | `0xf8F28826d4837e10fc9eD0d7787F763725F10378` | `0xc4c40096bf36620fafdb166f7328f84c6907a60392fc3321fb66ab345b99dafc` |
| Price guard | `0xADB3BD2222dBCd08ab78Bd7BD2BDbb6Adf043915` | `0x08599108bd65ee9d3f87e6431dd3e6fa5ad1e25cf44cb597041a35836c79bc39` |
| ETH/USD oracle | `0xB1115B9d0c409d6bCbb8d2483B2Cc0C425679754` | `0x0f34766397d79c63a443067d266f6cddce1107ad410fc75f68293c0386412bb7` |

## Consumer requirements

- Preserve prior generations under explicit historical keys for existing projects.
- Use the public Pons factory above for both ordinary and Project Pons launches.
- Use the agnostic Sinjoh fee router for Project launch fee routing and Funding Bands destinations.
- Discover the deterministic liquid-votes wrapper from the Project record for liquid governance and holder airdrops.
- Treat Treasury, staking, Airdrop, and Raffle as independent optional modules.
- Validate every address and runtime code hash against the signed promotion before enabling launch.
- Use two independent Robinhood Chain RPC providers for production preflight.
