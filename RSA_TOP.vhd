library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RNS_PKG.all;
use work.RSA_PKG.all;

-- =============================================================================
-- RSA_TOP
--
-- Single top-level RSA entity. Instantiates:
--   * RSA_KEYGEN  -> generates (N, e, d) at runtime from a PRNG seed
--   * RSA         -> performs modular exponentiation (M^exp mod N) via
--                    MOD_MONTGOMERY_EXP
--
-- The user only has to supply the message (and say encrypt or decrypt).
-- The rest happens internally.
--
-- Typical flow:
--   1. Load a non-zero seed:   set `seed`, pulse `load` for 1 cycle.
--   2. Generate a key pair:    pulse `gen_keys`; wait until `keys_ready = '1'`.
--   3. For every message:      drive `i_message` and `mode`
--                              ('0' = encrypt with e, '1' = decrypt with d),
--                              pulse `start`, wait for `o_done`, read
--                              `o_result`. Keys stay latched between ops;
--                              pulse `gen_keys` again only for a fresh pair.
--
-- Generics:
--   PRIME_WIDTH   : bit-width of the two primes p and q (default 16).
--   NUM_WITNESSES : Miller-Rabin rounds (default 4).
--
-- Constraint: 2 * PRIME_WIDTH must be <= MOD_WIDTH (from RSA_PKG, = 32),
-- because the underlying RSA core uses an MOD_WIDTH-bit exponent port.
-- So PRIME_WIDTH <= 16 for the current RSA_PKG settings.
-- The generated keys (N, e, d) are exposed on o_N / o_e / o_d for
-- observation / debug.
-- =============================================================================

entity RSA_TOP is
  generic(
    PRIME_WIDTH   : positive := 16;
    NUM_WITNESSES : positive := 4
  );
  port(
    clk        : in  std_logic;
    rst        : in  std_logic;

    -- Key-generation interface
    seed       : in  unsigned(127 downto 0);              -- PRNG seed (non-zero)
    load       : in  std_logic;                           -- seed load pulse
    gen_keys   : in  std_logic;                           -- request a new key pair
    keys_ready : out std_logic;                           -- '1' when keys are valid

    -- Encrypt/decrypt interface
    i_message  : in  unsigned(2*PRIME_WIDTH-1 downto 0);
    mode       : in  std_logic;                           -- '0'=encrypt  '1'=decrypt
    start      : in  std_logic;                           -- begin one operation
    o_done     : out std_logic;                           -- operation complete (1 cycle)
    o_result   : out unsigned(2*PRIME_WIDTH-1 downto 0);

    -- Key observation
    o_N        : out unsigned(2*PRIME_WIDTH-1 downto 0);
    o_e        : out unsigned(2*PRIME_WIDTH-1 downto 0);
    o_d        : out unsigned(2*PRIME_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RSA_TOP is

  constant KEY_WIDTH : positive := 2 * PRIME_WIDTH;

  -- Elaboration-time sanity check: the RSA core's exponent port is MOD_WIDTH
  -- bits, so the generated d (up to KEY_WIDTH bits) has to fit.
  assert KEY_WIDTH <= MOD_WIDTH
    report "RSA_TOP: 2*PRIME_WIDTH must be <= MOD_WIDTH (from RSA_PKG)."
    severity failure;

  -- -----------------------------------------------------------------
  -- RSA_KEYGEN interface
  -- -----------------------------------------------------------------
  signal kg_start : std_logic := '0';
  signal kg_done  : std_logic;
  signal kg_N     : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_e     : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_d     : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_valid : std_logic;

  -- Latched key pair
  signal N_reg     : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal e_reg     : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal d_reg     : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal have_keys : std_logic := '0';

  -- -----------------------------------------------------------------
  -- RSA core (modular exponentiation) interface
  -- Uses the fixed widths from RSA_PKG: INT_WIDTH for data, MOD_WIDTH for exp.
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
    S_IDLE,         -- No keys yet
    S_KG_RUN,       -- RSA_KEYGEN busy
    S_READY,        -- Keys latched, waiting for start / gen_keys
    S_PREP,         -- Stage RSA-core inputs
    S_LAUNCH,       -- Pulse start to RSA core
    S_WAIT_RSA,     -- Wait for rsa_done
    S_DONE_OUT      -- Drive o_done for one cycle
  );
  signal state : state_t := S_IDLE;

begin

  -- -----------------------------------------------------------------
  -- Child instantiations
  -- -----------------------------------------------------------------
  U_KEYGEN : entity work.RSA_KEYGEN
    generic map(
      PRIME_WIDTH   => PRIME_WIDTH,
      NUM_WITNESSES => NUM_WITNESSES
    )
    port map(
      clk     => clk,
      rst     => rst,
      start   => kg_start,
      seed    => seed,
      load    => load,
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

  -- -----------------------------------------------------------------
  -- Key observation outputs
  -- -----------------------------------------------------------------
  o_N        <= N_reg;
  o_e        <= e_reg;
  o_d        <= d_reg;
  keys_ready <= have_keys;

  -- -----------------------------------------------------------------
  -- Master FSM
  -- -----------------------------------------------------------------
  process(clk, rst)
  begin
    if rst = '1' then
      state     <= S_IDLE;
      kg_start  <= '0';
      rsa_start <= '0';
      rsa_msg   <= (others => '0');
      rsa_exp   <= (others => '0');
      rsa_N     <= (others => '0');
      msg_reg   <= (others => '0');
      mode_reg  <= '0';
      N_reg     <= (others => '0');
      e_reg     <= (others => '0');
      d_reg     <= (others => '0');
      have_keys <= '0';
      o_done    <= '0';
      o_result  <= (others => '0');

    elsif rising_edge(clk) then
      -- Default: single-cycle pulses
      kg_start  <= '0';
      rsa_start <= '0';
      o_done    <= '0';

      case state is

        -- -------------------------------------------------------
        when S_IDLE =>
          if gen_keys = '1' then
            kg_start  <= '1';
            have_keys <= '0';
            state     <= S_KG_RUN;
          end if;

        -- -------------------------------------------------------
        when S_KG_RUN =>
          if kg_done = '1' then
            if kg_valid = '1' then
              N_reg     <= kg_N;
              e_reg     <= kg_e;
              d_reg     <= kg_d;
              have_keys <= '1';
              state     <= S_READY;
            else
              -- gcd(e, phi) /= 1 or similar; retry automatically.
              kg_start <= '1';
              state    <= S_KG_RUN;
            end if;
          end if;

        -- -------------------------------------------------------
        when S_READY =>
          if gen_keys = '1' then
            have_keys <= '0';
            kg_start  <= '1';
            state     <= S_KG_RUN;
          elsif start = '1' then
            -- Latch the per-operation inputs.
            msg_reg  <= i_message;
            mode_reg <= mode;
            state    <= S_PREP;
          end if;

        -- -------------------------------------------------------
        -- Drive the RSA core inputs at their native widths.
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
