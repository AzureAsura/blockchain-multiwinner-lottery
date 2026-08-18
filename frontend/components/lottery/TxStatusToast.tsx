'use client'

import { useEffect, useId, useRef } from 'react'
import { toast } from 'sonner'

type TxStatus = 'idle' | 'pending' | 'confirming' | 'success' | 'error'

type TxStatusToastProps = {
  isPending: boolean
  isConfirming: boolean
  isSuccess: boolean
  error: string | null
  pendingMessage: string
  confirmingMessage: string
  successMessage: string
}

/** Renders nothing — drives a single sonner toast through a transaction's pending/confirming/success/error lifecycle. */
export function TxStatusToast({
  isPending,
  isConfirming,
  isSuccess,
  error,
  pendingMessage,
  confirmingMessage,
  successMessage,
}: TxStatusToastProps) {
  const toastId = useId()
  const lastStatus = useRef<TxStatus>('idle')

  useEffect(() => {
    if (error) {
      if (lastStatus.current !== 'error') {
        toast.error(error, { id: toastId })
        lastStatus.current = 'error'
      }
      return
    }

    if (isSuccess) {
      if (lastStatus.current !== 'success') {
        toast.success(successMessage, { id: toastId })
        lastStatus.current = 'success'
      }
      return
    }

    if (isConfirming) {
      if (lastStatus.current !== 'confirming') {
        toast.loading(confirmingMessage, { id: toastId })
        lastStatus.current = 'confirming'
      }
      return
    }

    if (isPending) {
      if (lastStatus.current !== 'pending') {
        toast.loading(pendingMessage, { id: toastId })
        lastStatus.current = 'pending'
      }
      return
    }

    lastStatus.current = 'idle'
  }, [isPending, isConfirming, isSuccess, error, toastId, pendingMessage, confirmingMessage, successMessage])

  return null
}
