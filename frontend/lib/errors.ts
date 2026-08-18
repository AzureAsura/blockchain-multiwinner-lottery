import { BaseError, ContractFunctionRevertedError, UserRejectedRequestError, formatEther } from 'viem'

const ERROR_MESSAGES: Record<string, string> = {
  Lottery__NotOpen: 'A draw is currently in progress, ticket purchases are paused.',
  Lottery__StalePrice: 'The ETH/USD oracle price is stale. Please try again shortly.',
  Lottery__NothingToClaim: 'There is no prize available to claim.',
  Lottery__RefundFailed: 'ETH transfer failed — your wallet rejected the funds.',
  Lottery__ClaimFailed: 'ETH transfer failed — your wallet rejected the funds.',
}

/**
 * Turns a contract simulate/write error into a user-facing message.
 * Returns null when the user simply cancelled in their wallet — that isn't an error to surface.
 */
export function describeContractError(error: unknown): string | null {
  if (error instanceof BaseError) {
    if (error.walk((e) => e instanceof UserRejectedRequestError)) return null

    const revertError = error.walk((e) => e instanceof ContractFunctionRevertedError)
    if (revertError instanceof ContractFunctionRevertedError) {
      const errorName = revertError.data?.errorName

      if (errorName === 'Lottery__InsufficientPayment') {
        const [required, sent] = (revertError.data?.args ?? []) as [bigint, bigint]
        return `Payment is short by ${formatEther(required - sent)} ETH of the current ticket price.`
      }

      if (errorName && errorName in ERROR_MESSAGES) return ERROR_MESSAGES[errorName]
      if (errorName) return `Transaction rejected by the contract: ${errorName}.`
    }

    return error.shortMessage
  }

  if (error instanceof Error) return error.message
  return 'An unknown error occurred.'
}
