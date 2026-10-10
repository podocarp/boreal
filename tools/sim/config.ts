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
  RESCUE: {
    COLLAPSE_DAY: 10, // day 10 without rescue → exposure-collapse end
    FLARE_WINDOW_H: 1.0, // flare counts for a pass if used within this window
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
    RADIUS_M: 0.35,
    TURN_RATE_RADPS: 10,
  },

  /** Needs decay/pacing — docs/DESIGN-needs.md "Numbers v1". Rates per GAME HOUR. */
  NEEDS: {
    HYDRATION_DECAY_PER_H: 1.75, // full → empty ≈ 2.4 days
    HUNGER_DECAY_PER_H: 1.0, // ≈ 4 days
    ENERGY_DECAY_PER_H: 4.0, // ≈ 25 h awake
    SHIVER_HUNGER_MUL: 1.5,
    SLEEP_RESTORE_PER_H: 15, // ~7 h to full when warm+fed
    DEBUFF_FROM: 45, // debuffs start here
    CRITICAL_BAND: 15,
    CRITICAL_THIRST_HP_PER_H: 1.5, // ~8-10 h at 0 → death
    CRITICAL_HUNGER_HP_PER_H: 0.5, // ~20 h at 0
    REGEN_HP_PER_H: 2,
    AUTO_SIP_BELOW: 60, // auto-sip engages below this
    AUTO_SIP_POINTS_PER_H: 35,
    HYDRATION_PER_LITER: 50, // 1 L restores 50 points
    /** Craving curve (Raft-style): food restores base * (1 + K*(1 - hunger/100)).
     * Makes grazing pointless and desperate meals huge. 0 disables. */
    CRAVING_K: 0.8,
    DIFF: { bushman: 0.7, survivorman: 1.3 },
  },

  /** Thermoregulation — °C/h budget model (see needs.ts tuning targets). */
  THERMO: {
    COLD_C: 36.0,
    VERY_COLD_C: 34.5,
    HYPOTHERMIA_C: 33.0,
    LOSS_K: 0.07, // loss = LOSS_K * max(0,-feels) / insulation — tuned: walking at feels −25 °C ≈ neutral, idle at −20 → hypothermia in ~5 h
    BASE_INSULATION: 1.0, // dry winter clothing
    SHELTER_INSUL_BONUS: 0.8, // good debris shelter + bedding at shelterInsul=1
    WETNESS_INSUL_PENALTY: 0.6, // soaked clothing keeps 40% insulation
    METABOLIC_HEAT: 0.6, // °C/h at full calories
    EXERTION_HEAT: 1.2, // walking
    FIRE_HEAT_GAIN: 2.6, // at fireWarmth=1 (a good fire beats a −35 °C windchill)
    MAX_COOL_PER_H: 2.5,
    MAX_WARM_PER_H: 1.5,
    HYPO_HP_PER_H: 8, // ×3 below 30 °C
  },

  /** Diurnal air temperature (°C): base ± swing, peak 14:00. */
  CLIMATE: {
    TEMP_SWING_C: 6,
    /** storm events (S5): wind multiplier + wetness gain */
    WIND_NIGHT_MUL: 1.4,
  },
} as const;
