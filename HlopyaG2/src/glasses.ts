import {
  CreateStartUpPageContainer,
  MenuContainerProperty,
  MenuItemProperty,
  OsEventTypeList,
  StartUpPageCreateResult,
  TextContainerProperty,
  TextContainerUpgrade,
  type EvenAppBridge,
} from '@evenrealities/even_hub_sdk'

// G2 canvas is 576x288. One full-screen text container that also captures
// taps; actions that need more than a tap live in the contextual menu.
const SCREEN = { containerID: 1, containerName: 'hlopya-status' }

export const MenuItem = { Toggle: 1, Sync: 2, Discard: 3 } as const

export type GlassesState = {
  recording: boolean
  seconds: number
  speaking: 'self' | 'other' | 'unknown' | null
  pending: number
  note: string
}

export async function createGlassesPage(bridge: EvenAppBridge, state: GlassesState): Promise<boolean> {
  const result = await bridge.createStartUpPageContainer(
    new CreateStartUpPageContainer({
      containerTotalNum: 1,
      textObject: [
        new TextContainerProperty({
          xPosition: 16,
          yPosition: 16,
          width: 544,
          height: 256,
          ...SCREEN,
          content: render(state),
          isEventCapture: 1,
        }),
      ],
      menuObject: new MenuContainerProperty({
        menuItems: [
          new MenuItemProperty({ itemID: MenuItem.Toggle, itemName: 'Start / stop' }),
          new MenuItemProperty({ itemID: MenuItem.Sync, itemName: 'Send pending' }),
          new MenuItemProperty({ itemID: MenuItem.Discard, itemName: 'Discard recording' }),
        ],
      }),
    }),
  )
  return result === StartUpPageCreateResult.success
}

let lastRendered = ''

export async function updateGlasses(bridge: EvenAppBridge, state: GlassesState): Promise<void> {
  const content = render(state)
  if (content === lastRendered) return
  lastRendered = content
  await bridge.textContainerUpgrade(new TextContainerUpgrade({ ...SCREEN, content }))
}

// Taps arrive as text/sys events; CLICK_EVENT is protobuf value 0, which the
// host often omits, so a missing eventType also counts as a click.
export function isTap(eventType: OsEventTypeList | undefined): boolean {
  return eventType === undefined || eventType === OsEventTypeList.CLICK_EVENT
}

function render(s: GlassesState): string {
  const lines = ['HLOPYA', '']
  if (s.recording) {
    lines.push(`● REC  ${clock(s.seconds)}`)
    lines.push(s.speaking === 'self' ? 'You are speaking' : s.speaking === 'other' ? 'Them speaking' : ' ')
    lines.push('', 'Tap: stop & send')
  } else {
    lines.push('Ready')
    lines.push(s.pending > 0 ? `${s.pending} waiting to send` : ' ')
    lines.push('', 'Tap: start recording')
  }
  if (s.note) lines.push('', s.note)
  return lines.join('\n')
}

export function clock(seconds: number): string {
  const total = Math.floor(seconds)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const sec = total % 60
  const mm = String(m).padStart(2, '0')
  const ss = String(sec).padStart(2, '0')
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`
}
