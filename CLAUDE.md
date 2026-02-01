# ColonyGame Development Plan

## Project Overview

A real-time multiplayer colony survival game built with Elixir/Phoenix LiveView and OTP architecture.

**Tech Stack:** Elixir 1.18, Phoenix 1.7.19, LiveView, PostgreSQL (not yet integrated), Tailwind CSS

## Game Design Principles

### Anonymous Players
- Players remain anonymous (no usernames displayed)
- Anonymous chat is a core strategic feature
- Players can bluff, form secret alliances, or deceive others
- Identity is hidden to enable social deduction and strategy
- Do NOT add features that reveal player identity

### UI/UX Design Goals
- Intuitive graphical interface
- Clear visual feedback for actions and state changes
- Mobile-friendly responsive design (works on iOS)
- Real-time updates without page refresh (LiveView)

#### Layout: Hybrid (Game Map + UI Panels)
- Central game map/colony view (top-down or isometric)
- Resource bars at top
- Action buttons at bottom
- Chat panel (collapsible sidebar or bottom drawer)
- Status notifications as toasts/overlays

#### UI Elements
- [ ] Resource bars (food=green, water=blue, energy=yellow)
- [ ] Central colony/map view with clickable locations
- [ ] Action buttons (large, touch-friendly for mobile)
- [ ] Anonymous player dots/indicators on map
- [ ] Chat panel (anonymous, collapsible)
- [ ] Toast notifications for events
- [ ] Foraging progress indicator

#### Visual Style: Low-Fi Colorful
**Inspiration:** The Tower (iOS tower defense game)
- Simple geometric shapes (circles, rounded rectangles)
- Bold, saturated colors on dark or muted background
- Clear visual hierarchy - important things pop
- Smooth animations for state changes
- Minimal text, icons where possible
- Touch-friendly hit targets (44px+ for mobile)

## Current State

### Implemented
- OTP-based multiplayer architecture (GenServer, DynamicSupervisor, Registry)
- Real-time game tick system (5-second intervals)
- Resource management (food, water, energy - initialized at 100)
- Foraging mechanic with time-based completion (5 ticks)
- Food regrowth system
- Real-time UI updates via PubSub
- Anonymous player sessions
- Rules engine with state machine (`:idle` <-> `:foraging`)

### Not Implemented
- Database persistence (all state in memory, lost on restart)
- Player authentication
- Water/energy consumption mechanics
- Multiple foraging locations
- Colony buildings/structures
- Player interaction/visibility
- Crafting, trading systems

## Known Issues

### Bug: ForagingServer tick comparison
**File:** `lib/colony_game/game/foraging_server.ex:44`
**Issue:** Uses `=` instead of `==`, causing food to regrow every tick instead of every 30 ticks
```elixir
# Current (broken):
if(tick_counter = @tick_interval) do

# Should be:
if(tick_counter == @tick_interval) do
```

### Missing Tests
- `PlayerProcess` - 0% coverage
- `TickServer` - 0% coverage
- `ForagingServer` - 0% coverage
- `GameLive` (LiveView) - 0% coverage
- `page_controller_test.exs` is empty

## Development Plan

### Phase 1: CI/CD & Dev Deployment (Priority: Immediate)
**Hosting:** Fly.io

1. Set up GitHub Actions workflow
   - Run tests on PR/push
   - Build Elixir release
2. Configure Fly.io app (`fly launch`)
3. Set up Fly Postgres database
4. Configure secrets (SECRET_KEY_BASE, DATABASE_URL)
5. Auto-deploy main branch via GitHub Actions
6. Document deployment URL

**Goal:** View live progress on a dev URL after each merge

### Phase 2: Stabilization
1. Fix ForagingServer tick comparison bug
2. Add tests for PlayerProcess
3. Add tests for ForagingServer
4. Add tests for TickServer
5. Implement water/energy consumption (already defined, not used)

### Phase 3: Persistence
1. Create Ecto schemas for Player, Resources, GameState
2. Add database migrations
3. Persist player state on updates
4. Load player state on reconnect
5. Add player authentication (optional: can start with session-based)

### Phase 4: Gameplay Expansion
1. Multiple foraging locations with different resources
2. Water sources (wells, rivers)
3. Energy mechanics (rest, shelter)
4. Basic inventory system
5. Colony buildings (shelter, storage, well)

### Phase 5: Multiplayer Features
1. Show other players in UI
2. Anonymous chat system
3. Resource sharing/trading
4. Collaborative building

## Architecture Notes

### Key Files
- `lib/colony_game/game/rules.ex` - Core game logic, state machine
- `lib/colony_game/game/player_process.ex` - Per-player GenServer
- `lib/colony_game/game/tick_server.ex` - Game loop (5s interval)
- `lib/colony_game/game/foraging_server.ex` - Food source management
- `lib/colony_game_web/live/game_live.ex` - Main LiveView UI

### Data Flow
```
User Action -> LiveView -> PlayerProcess -> Rules.check()
                                         -> State Update
                                         -> PubSub Broadcast
                                         -> LiveView Update
```

### OTP Supervision Tree
```
Application
├── PubSub
├── Registry
├── PlayerSupervisor (DynamicSupervisor)
│   └── PlayerProcess (one per player)
├── TickServer
├── ForagingServer
└── Endpoint
```
