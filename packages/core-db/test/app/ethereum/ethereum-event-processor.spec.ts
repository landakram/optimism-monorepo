import '../../setup'

/* External Imports */
import { getLogger } from '@eth-optimism/core-utils'
import { createMockProvider, getWallets } from 'ethereum-waffle'

/* Internal Imports */
import { deployTokenContract, TestListener } from './utils'
import { EthereumEventProcessor } from '../../../src/app/ethereum'
import { EthereumEvent } from '../../../src/types/ethereum'
import { newInMemoryDB } from '../../../src/app'

const log = getLogger('ethereum-event-processor', true)

const timeout = 25_000
describe('EthereumEvent Subscription', () => {
  let provider
  let wallets
  let ownerWallet
  let recipientWallet

  const sendAmount = 100
  const initialSupply = 100_000

  let tokenContract
  let eventProcessor: EthereumEventProcessor
  let eventListener: TestListener<EthereumEvent>

  describe('1 Confirm', () => {
    beforeEach(async () => {
      provider = createMockProvider()
      wallets = getWallets(provider)
      ownerWallet = wallets[0]
      recipientWallet = wallets[1]

      log.debug(`Connection info: ${JSON.stringify(provider.connection)}`)

      tokenContract = await deployTokenContract(ownerWallet, initialSupply)

      eventProcessor = new EthereumEventProcessor(newInMemoryDB())
      eventListener = new TestListener<EthereumEvent>()
    })

    it('deploys correctly', async () => {
      const ownerBalance = +(await tokenContract.balanceOf(ownerWallet.address))
      ownerBalance.should.equal(initialSupply)
    })

    it('processes new events', async () => {
      await eventProcessor.subscribe(
        tokenContract,
        'Transfer',
        eventListener,
        false
      )

      await tokenContract.transfer(
        ownerWallet.address,
        recipientWallet.address,
        sendAmount
      )

      const events = await eventListener.waitForReceive()
      events.length.should.equal(1)
      const event: EthereumEvent = events[0]
      event.values['from'].should.equal(ownerWallet.address)
      event.values['to'].should.equal(recipientWallet.address)
      event.values['amount'].toNumber().should.equal(sendAmount)
    }).timeout(timeout)

    it('processes old events', async () => {
      await tokenContract.transfer(
        ownerWallet.address,
        recipientWallet.address,
        sendAmount
      )

      await tokenContract.provider.send('evm_mine', {
        jsonrpc: '2.0',
        id: 0,
      })

      await eventProcessor.subscribe(tokenContract, 'Transfer', eventListener)

      const events = await eventListener.waitForSyncToComplete()
      events.length.should.equal(1)
      const event: EthereumEvent = events[0]
      event.values['from'].should.equal(ownerWallet.address)
      event.values['to'].should.equal(recipientWallet.address)
      event.values['amount'].toNumber().should.equal(sendAmount)
    }).timeout(timeout)

    it('processes new and old', async () => {
      await tokenContract.transfer(
        ownerWallet.address,
        recipientWallet.address,
        sendAmount
      )

      await tokenContract.provider.send('evm_mine', {
        jsonrpc: '2.0',
        id: 0,
      })

      await eventProcessor.subscribe(tokenContract, 'Transfer', eventListener)

      let events = await eventListener.waitForReceive()
      events.length.should.equal(1)
      const event1 = events[0]

      await tokenContract.transfer(
        ownerWallet.address,
        recipientWallet.address,
        sendAmount * 2
      )

      events = await eventListener.waitForReceive()
      log.debug(
        `event 1: ${JSON.stringify(event1)}, rest: ${JSON.stringify(events)}`
      )
      events.length.should.equal(1)

      !events[0].values['amount']
        .toNumber()
        .should.not.equal(event1.values['amount'].toNumber())
    })
  })

  describe('Additional Confirms', () => {
    beforeEach(async () => {
      provider = createMockProvider()
      wallets = getWallets(provider)
      ownerWallet = wallets[0]
      recipientWallet = wallets[1]

      log.debug(`Connection info: ${JSON.stringify(provider.connection)}`)

      tokenContract = await deployTokenContract(ownerWallet, initialSupply)

      eventProcessor = new EthereumEventProcessor(newInMemoryDB(), 0, 2)
      eventListener = new TestListener<EthereumEvent>()
    })

    it('does not process new events without 2 confirms', async () => {
      await eventProcessor.subscribe(
        tokenContract,
        'Transfer',
        eventListener,
        false
      )

      await tokenContract.transfer(
        ownerWallet.address,
        recipientWallet.address,
        sendAmount
      )

      const events = await eventListener.waitForReceive(1, 10_000)
      events.length.should.equal(0)
    }).timeout(timeout)

    it('does process new events with 2 confirms', async () => {
      await eventProcessor.subscribe(
        tokenContract,
        'Transfer',
        eventListener,
        false
      )

      await tokenContract.transfer(
        ownerWallet.address,
        recipientWallet.address,
        sendAmount
      )

      await tokenContract.updateMeaninglessHash('0x111111111111')

      const events = await eventListener.waitForReceive()
      events.length.should.equal(1)
      const event: EthereumEvent = events[0]
      event.values['from'].should.equal(ownerWallet.address)
      event.values['to'].should.equal(recipientWallet.address)
      event.values['amount'].toNumber().should.equal(sendAmount)
    }).timeout(timeout)
  })
})
