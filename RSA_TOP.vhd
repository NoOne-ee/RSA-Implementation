library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RSA_PKG.all;

-- =============================================================================
-- RSA_TOP
--
-- Single top-level RSA entity. Instantiates:
--   * RSA_KEYGEN  -> generates (N, e, d) once on power-up / reset from an
--                    internal constant seed (no user interaction needed)
--   * RSA         -> performs M^exp mod N via MOD_MONTGOMERY_EXP
--
-- The ONLY user-facing inputs are:
--   clk, rst, i_message, mode, start
--
-- PRIME_WIDTH and NUM_WITNESSES are defined as constants in RSA_PKG so the
-- whole design agrees on one setting. Change them in the package to rebuild
-- with different key sizes.
--
-- Flow on the FPGA:
--   1. After reset, the block automatically seeds its PRNG, runs key
--      generation, and latches (N, e, d). This takes some number of clock
--      cycles but happens without any user action.
--   2. While keys are not yet valid, any start pulse is silently ignored.
--      Once keys are ready the block is able to serve encrypt/decrypt ops.
--   3. To encrypt or decrypt: drive i_message and mode ('0'=encrypt,
--      '1'=decrypt), pulse start for one cycle, wait for o_done = '1',
--      read o_result. Keys stay latched for all subsequent operations.
--
-- The generated keys are also exposed on o_N / o_e / o_d for debug (these
-- are outputs; they don't add any input pins). o_N going non-zero is a
-- handy way for a connected host / testbench to know keygen has completed.
--
-- NOTE on the seed: there is no true-random source on a stock FPGA, so the
-- PRNG has to be seeded by a compile-time constant (C_SEED below). That
-- means: identical bitstream -> identical keys on every power-up. For a
-- class / demo project that's fine. To get different keys, either:
--   - change C_SEED and rebuild, or
--   - add an entropy source (ring-oscillator TRNG, etc.) later and drive
--     the PRNG seed from it.
--
-- Constraint: 2 * PRIME_WIDTH must be <= MOD_WIDTH (from RSA_PKG, = 32),
-- because the RSA core uses an MOD_WIDTH-bit exponent port. So with the
-- current RSA_PKG settings, PRIME_WIDTH <= 16.
-- =============================================================================

entity RSA_TOP is
  port(
    clk        : in  std_logic;
    rst        : in  std_logic;

    -- The only user-driven inputs:
    i_message  : in  unsigned(2*PRIME_WIDTH-1 downto 0);
    mode       : in  std_logic;                          -- '0'=encrypt  '1'=decrypt
    start      : in  std_logic;                          -- pulse to run one op

    -- Status / data outputs:
    o_done     : out std_logic;                          -- 1-cycle pulse when o_result is valid
    o_result   : out unsigned(2*PRIME_WIDTH-1 downto 0);

    -- Debug (optional): generated key pair
    o_N        : out unsigned(2*PRIME_WIDTH-1 downto 0);
    o_e        : out unsigned(2*PRIME_WIDTH-1 downto 0);
    o_d        : out unsigned(2*PRIME_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RSA_TOP is

  constant KEY_WIDTH : positive := 2 * PRIME_WIDTH;

  -- Built-in PRNG seed. Any non-zero 128-bit constant is fine.
  -- Change it and rebuild to get a different key pair.
  constant C_SEED : unsigned(127 downto 0) := x"DEADBEEFCAFEBABE1234567890ABCDEF";

  -- -----------------------------------------------------------------
  -- RSA_KEYGEN interface
  -- -----------------------------------------------------------------
  signal kg_start : std_logic := '0';
  signal kg_load  : std_logic := '0';
  signal kg_done  : std_logic;
  signal kg_N     : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_e     : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_d     : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_valid : std_logic;

  -- Latched key pair
  signal N_reg    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal e_reg    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal d_reg    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');

  -- -----------------------------------------------------------------
  -- RSA core (modular exponentiation) interface
  -- -----------------------------------------------------------------
  signal rsa_start  : std_logic := '0';
  signal rsa_done   : std_logic;
  signal rsa_msg    : unsigned(INT_WIDTH-1 downto 0) := (others => '0');
  signal rsa_exp    : unsigned(MOD_WIDTH-1 downto 0) := (others => '0');
  signal rsa_N      : unsigned(INT_WIDTH-1 downto 0) := (others => '0');
  signal rsa_result : unsigned(INT_WIDTH-1 downto 0);

  -- Per-operation latches
  signal msg_reg  : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal mode_reg : std_logic := '0';

  -- Master FSM
  type state_t is (
    S_SEED_LOAD,   -- pulse the PRNG load with the constant seed
    S_KG_LAUNCH,   -- pulse keygen start
    S_KG_RUN,      -- keygen working; if invalid, retry
    S_READY,       -- keys valid, waiting for user start
    S_PREP,        -- stage RSA-core inputs
    S_LAUNCH,      -- pulse RSA-core start
    S_WAIT_RSA,    -- wait for RSA-core done
    S_DONE_OUT     -- drive o_done for one cycle
  );
  signal state : state_t := S_SEED_LOAD;

begin

  -- -----------------------------------------------------------------
  -- Child instantiations
  -- -----------------------------------------------------------------
  U_KEYGEN : entity work.RSA_KEYGEN
    port map(
      clk     => clk,
      rst     => rst,
      start   => kg_start,
      seed    => C_SEED,     -- internal, hard-coded
      load    => kg_load,    -- pulsed once from the FSM
      o_done  => kg_done,
      o_N     => kg_N,
      o_e     => kg_e,
      o_d     => kg_d,
      o_valid => kg_valid
    );

  U_RSA : entity work.RSA
    port map(
      clk       => clk,
      rst       => rst,
      start     => rsa_start,
      i_message => rsa_msg,
      i_exp     => rsa_exp,
      i_N       => rsa_N,
      o_done    => rsa_done,
      o_result  => rsa_result
    );

  -- Debug outputs
  o_N <= N_reg;
  o_e <= e_reg;
  o_d <= d_reg;

  -- -----------------------------------------------------------------
  -- Master FSM
  -- -----------------------------------------------------------------
  process(clk, rst)
  begin
    if rst = '1' then
      state     <= S_SEED_LOAD;
      kg_start  <= '0';
      kg_load   <= '0';
      rsa_start <= '0';
      rsa_msg   <= (others => '0');
      rsa_exp   <= (others => '0');
      rsa_N     <= (others => '0');
      msg_reg   <= (others => '0');
      mode_reg  <= '0';
      N_reg     <= (others => '0');
      e_reg     <= (others => '0');
      d_reg     <= (others => '0');
      o_done    <= '0';
      o_result  <= (others => '0');

    elsif rising_edge(clk) then
      -- Default: single-cycle pulses
      kg_start  <= '0';
      kg_load   <= '0';
      rsa_start <= '0';
      o_done    <= '0';

      case state is

        -- -------------------------------------------------------
        -- Auto-seed the PRNG with C_SEED, one cycle after reset.
        when S_SEED_LOAD =>
          kg_load <= '1';
          state   <= S_KG_LAUNCH;

        -- -------------------------------------------------------
        -- Kick off key generation automatically.
        when S_KG_LAUNCH =>
          kg_start <= '1';
          state    <= S_KG_RUN;

        -- -------------------------------------------------------
        -- Wait for the keygen. If it failed (e.g. gcd(e,phi) /= 1),
        -- retry automatically.
        when S_KG_RUN =>
          if kg_done = '1' then
            if kg_valid = '1' then
              N_reg <= kg_N;
              e_reg <= kg_e;
              d_reg <= kg_d;
              state <= S_READY;
            else
              kg_start <= '1';
              state    <= S_KG_RUN;
            end if;
          end if;

        -- -------------------------------------------------------
        -- Keys are ready. Wait for a user start pulse.
        -- (If start is pulsed before we reach this state, it is
        -- silently ignored, which is exactly what we want.)
        when S_READY =>
          if start = '1' then
            msg_reg  <= i_message;
            mode_reg <= mode;
            state    <= S_PREP;
          end if;

        -- -------------------------------------------------------
        when S_PREP =>
          rsa_msg <= resize(msg_reg, INT_WIDTH);
          rsa_N   <= resize(N_reg,  INT_WIDTH);
          if mode_reg = '1' then
            rsa_exp <= resize(d_reg, MOD_WIDTH);   -- decrypt
          else
            rsa_exp <= resize(e_reg, MOD_WIDTH);   -- encrypt
          end if;
          state <= S_LAUNCH;

        -- -------------------------------------------------------
        when S_LAUNCH =>
          rsa_start <= '1';
          state     <= S_WAIT_RSA;

        -- -------------------------------------------------------
        when S_WAIT_RSA =>
          if rsa_done = '1' then
            -- Result is < N < 2^KEY_WIDTH, so upper bits are zero.
            o_result <= rsa_result(KEY_WIDTH-1 downto 0);
            state    <= S_DONE_OUT;
          end if;

        -- -------------------------------------------------------
        when S_DONE_OUT =>
          o_done <= '1';
          state  <= S_READY;

      end case;
    end if;
  end process;

end RTL;
