/**
 * BOREAL — simulation config: ALL tunables live here.
 * Design docs reference these constant names. Units are noted per constant.
 * Sprint 0: placeholder values only; S2 (needs) and beyond will set real numbers
 * per docs/DESIGN-needs.md.
 */
export const CONFIG = {
  /** Fixed simulation timestep in seconds. */
  SIM_DT: 0.25,

  TIME: {
    /** Real seconds per in-game hour (day ≈ 10-15 real min => 24h in 600-900s). */
    REAL_SECONDS_PER_GAME_HOUR: 30,
    /** Days until the rescue search window opens. */
    RESCUE_WINDOW_DAY: 7,
  },

  WORLD: {
    /** Terrain half-size in meters. */
    SIZE_M: 400,
    /** Base air temperature band, °C (shoulder-season subarctic). S2 will drive this diurnally. */
    TEMP_BASE_C: -12,
    WIND_BASE_KMH: 10,
  },

  PLAYER: {
    WALK_SPEED_MPS: 1.4,
    RUN_SPEED_MPS: 3.2,
    EYE_HEIGHT_M: 1.65,
  },
} as const;
