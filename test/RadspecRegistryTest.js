const RadspecRegistry = artifacts.require('RadspecRegistry')

const { hash } = require('eth-ens-namehash')
const deployDAO = require('./helpers/deployDAO')
const BN = require('bn.js')

const ANY_ADDRESS = '0xffffffffffffffffffffffffffffffffffffffff'
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
const bigExp = (number, decimals) => new BN(number).mul(new BN(10).pow(new BN(decimals)))

const getLog = (receipt, logName, argName) => {
  const log = receipt.logs.find(({ event }) => event === logName)
  return log ? log.args[argName] : null
}

const deployedContract = receipt => getLog(receipt, 'NewAppProxy', 'proxy')

contract('RadspecRegistry', () => {
  let accounts, appManager
  let SET_BENEFICIARY_ROLE, SET_FEE_PERCENTAGE_ROLE, SET_ARBITRATOR_ROLE, SET_UPSERT_FEE_ROLE,
    STAKED_UPSERT_ENTRY_ROLE, UPSERT_ENTRY_ROLE, REMOVE_ENTRY_ROLE
  let radspecRegistryBase, radspecRegistry

  before('deploy base radspecRegistry', async () => {
    accounts = await web3.eth.getAccounts();
    appManager = accounts[0]

    radspecRegistryBase = await RadspecRegistry.new()
    SET_BENEFICIARY_ROLE = await radspecRegistryBase.SET_BENEFICIARY_ROLE()
    SET_FEE_PERCENTAGE_ROLE = await radspecRegistryBase.SET_FEE_PERCENTAGE_ROLE()
    SET_ARBITRATOR_ROLE = await radspecRegistryBase.SET_ARBITRATOR_ROLE()
    SET_UPSERT_FEE_ROLE = await radspecRegistryBase.SET_UPSERT_FEE_ROLE()
    STAKED_UPSERT_ENTRY_ROLE = await radspecRegistryBase.STAKED_UPSERT_ENTRY_ROLE()
    UPSERT_ENTRY_ROLE = await radspecRegistryBase.UPSERT_ENTRY_ROLE()
    REMOVE_ENTRY_ROLE = await radspecRegistryBase.REMOVE_ENTRY_ROLE()
  })

  beforeEach('deploy dao and radspecRegistry', async () => {
    const { dao, acl } = await deployDAO(appManager, artifacts)

    const newAppInstanceReceipt = await dao.newAppInstance(hash('abc'), radspecRegistryBase.address, '0x', false, { from: appManager })
    radspecRegistry = await RadspecRegistry.at(deployedContract(newAppInstanceReceipt))
    await acl.createPermission(ANY_ADDRESS, radspecRegistry.address, SET_BENEFICIARY_ROLE, appManager, { from: appManager })

    // await radspecRegistry.initialize()
  })

  it('does the right thing', async () => {
    assert.isTrue(true)
  })
})