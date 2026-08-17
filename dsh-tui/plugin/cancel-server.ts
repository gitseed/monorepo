/**
 * dsh-tui-sdk-server: the stock SDK jsonrpc server plus `session/cancel`.
 *
 * Upstream's server routes only initialize/session-prompt/shutdown, so the
 * only interrupt an out-of-process client had was killing the runtime —
 * destroying the model's context. The cancellation seam exists on the agent
 * handle the server already holds: `agent.cancel({ kind: 'user' })`, exactly
 * what dsh's ACP bridge calls. This plugin subclasses the exported server
 * and routes the method; the turn settles as cancelled and the session
 * keeps its memory.
 *
 * Loaded by absolute path (the documented out-of-tree mechanism — see
 * deepseek-harness docs, develop/basic). Imports come from the runtime
 * executable's own snapshot so the classes are version-locked to the
 * runtime actually running; DSH_TUI_SNAPSHOT_BASE overrides the base if an
 * exe build relocates it. `this.sessions` is TypeScript-private upstream —
 * a plain property in the compiled class; a switch to real #private fields
 * would break this loudly (TypeError), not silently.
 */

const SNAPSHOT_BASE = process.env['DSH_TUI_SNAPSHOT_BASE']
  ?? '/snapshot/deepseek-harness/python/sdk-runtime/src/deepseek_harness_runtime/runtime/node/node_modules'

const { JsonRpcLineTransport } = await import(`${SNAPSHOT_BASE}/@deepseek-ai/dsh-sdk-protocol/lib/index.js`)
const { HarnessSdkJsonRpcServer } = await import(`${SNAPSHOT_BASE}/@deepseek-ai/dsh-sdk-jsonrpc-server/lib/index.js`)

export const name = 'dsh-tui-sdk-server'
export const inject = ['agents']

class CancellableSdkServer extends HarnessSdkJsonRpcServer {
  async handleRequest(method: string, params: Record<string, unknown> | undefined): Promise<unknown> {
    if (method === 'session/cancel') return this.cancelSession(params)
    return super.handleRequest(method, params)
  }

  async cancelSession(params: Record<string, unknown> | undefined): Promise<{ cancelled: boolean }> {
    const sessionId = params?.['sessionId']
    if (typeof sessionId !== 'string' || sessionId === '') {
      throw new Error('session/cancel requires a sessionId')
    }
    // Unknown ids are a no-op, mirroring the ACP bridge's contract.
    const rec = (this as any).sessions.get(sessionId)
    if (rec === undefined) return { cancelled: false }
    rec.handle.agent.cancel({ kind: 'user' })
    return { cancelled: true }
  }
}

/**
 * Mirrors the stock plugin's apply() exactly, constructing the subclass.
 * No Config schema: the loader treats it as optional, and the one option
 * is read directly.
 */
export function apply(ctx: any, config: { maxTokensAsSuccess?: boolean } | undefined): void {
  const rootFiber = ctx.root.fiber
  const transport = new JsonRpcLineTransport(process.stdin, process.stdout)
  const server = new CancellableSdkServer(ctx, transport, {
    maxTokensAsSuccess: config?.maxTokensAsSuccess ?? false,
  })

  let exitTask: Promise<void> | undefined
  const disposeAndExit = (): Promise<void> => {
    exitTask ??= (async () => {
      await Promise.allSettled([Promise.resolve().then(() => transport.flush())])
      await Promise.allSettled([Promise.resolve().then(() => rootFiber.dispose())])
      process.exit(0)
    })()
    return exitTask
  }

  transport.onRequest(async (method: string, params: Record<string, unknown> | undefined) => {
    const result = await server.handleRequest(method, params)
    if (method === 'shutdown') setImmediate(() => { void disposeAndExit() })
    return result
  })

  ctx.effect(() => {
    transport.start()
    return async () => {
      await server.shutdown()
      transport.close()
    }
  }, 'jsonrpc.serve')
}
