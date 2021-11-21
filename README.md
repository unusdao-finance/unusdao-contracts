# UnusDAO Smart Contracts

## Mainnet Contracts & Addresses

|Contract       | Addresss                                                                                                            | Notes   |
|:-------------:|:-------------------------------------------------------------------------------------------------------------------:|-------|
|UDO            |[0x08a1B706Bcd6e19D5A072E9594961607B31964D9](https://bscscan.com/address/0x08a1B706Bcd6e19D5A072E9594961607B31964D9)| Main Token Contract|
|sUDO           |[0x6FC187cDD16831FF1d04624A1FACcBFD3C07cc20](https://bscscan.com/address/0x6FC187cDD16831FF1d04624A1FACcBFD3C07cc20)| Staked UDO|
|Treasury       |[0x6a3EC0142F05667B3ef9296f388Ff4398E2e6B73](https://bscscan.com/address/0x6a3EC0142F05667B3ef9296f388Ff4398E2e6B73)| UnusDAO Treasury holds all the assets        |
|Staking |[0x6CebCe497F8C704D02580fab9787A05e12034104](https://bscscan.com/address/0x6CebCe497F8C704D02580fab9787A05e12034104)| Main Staking contract responsible for calling rebases every 9600 blocks|
|DAO            |[0xD21EeEd8775a816bCb0222F328eB4A026969D2Bf](https://bscscan.com/address/0xD21EeEd8775a816bCb0222F328eB4A026969D2Bf)|Storage Wallet for DAO under MS |

**Bonds**
- **_TODO_**: What are the requirements for creating a Bond Contract?
All LP bonds use the Bonding Calculator contract which is used to compute RFV. 

|Contract       | Addresss                                                                                                            | Notes   |
|:-------------:|:-------------------------------------------------------------------------------------------------------------------:|-------|
|Bond Calculator|[0xC7059A7e0A7a0307736CcE804b79D90be878Bffd](https://bscscan.com/address/0xC7059A7e0A7a0307736CcE804b79D90be878Bffd)| |
|BUSD/UDO Pancake-LPs Bond|[0x997F660C5B162b78C7e003D120380e21Dfe09332](https://bscscan.com/address/0x997F660C5B162b78C7e003D120380e21Dfe09332)| Manages mechhanism for thhe protocol to buy back its own liquidity from the pair. |

**DAO**

The DAO contract is guarded by a 4 of 7 multisig. That means any transaction for making DAO changes must be approved by at least 4 signers, of which we have 7 signers in total. The operation security for our DAO is thus protected from a single actor going rogue, because it takes a quorum of 4 to authorize any transaction like engaging in DAO swaps. The 7 signing addresses for the DAO are listed below.

Note that all signers can be verified on [bscscan](https://www.bscscan.com/address/0xD21EeEd8775a816bCb0222F328eB4A026969D2Bf#readProxyContract) as well as on [GnosisSafe](https://gnosis-safe.io/app/bnb:0xD21EeEd8775a816bCb0222F328eB4A026969D2Bf/settings/owners).

1. [0x7A80DEDFa974b6ae804f5E1c2140Ee06775a06bE](https://bscscan.com/address/0x997F660C5B162b78C7e003D120380e21Dfe09332)
2. [0xbF9D72b4eaF15151479299F336318C65701b04ad](https://bscscan.com/address/0xbF9D72b4eaF15151479299F336318C65701b04ad)
3. [0xb53dD777A649695bD72b8E438b8e6B30640271C1](https://bscscan.com/address/0xb53dD777A649695bD72b8E438b8e6B30640271C1)
4. [0xcBb47f51e8f2AD661c583105A03491e0e4433435](https://bscscan.com/address/0xcBb47f51e8f2AD661c583105A03491e0e4433435)
5. [0x64472E9D8166BF5bDea0Fe5Ce05C166D8A50DA9e](https://bscscan.com/address/0x64472E9D8166BF5bDea0Fe5Ce05C166D8A50DA9e)
6. [0x1151cd5827D15f3Fd5Bb7e409a95AD25E643c478](https://bscscan.com/address/0x1151cd5827D15f3Fd5Bb7e409a95AD25E643c478)
7. [0x2811a45f9C989570b0F354685cD6212471B512D0](https://bscscan.com/address/0x2811a45f9C989570b0F354685cD6212471B512D0)