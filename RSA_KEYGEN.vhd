-- =============================================================================
-- RSA_KEYGEN.vhd
-- RSA Key Generation Top-Level Block
--
-- Orchestrates RANDOM_GEN, MILLER_RABIN, and EXT_GCD to produce an RSA key pair.
--
-- Flow:
--   1. Generate random candidate p (PRIME_WIDTH bits) using RANDOM_GEN
--   2. Test p with MILLER_RABIN; if composite, go to step 1
--   3. Generate random candidate q using RANDOM_GEN
--   4. Test q with MILLER_RABIN; if composite, go to step 3
--   5. Compute N = p * q (KEY_WIDTH = 2*PRIME_WIDTH bits)
--   6. Compute phi = (p-1) * (q-1)
--   7. Compute d = e^(-1) mod phi using EXT_GCD (e = 65537 fixed)
--   8. Output N, e, d
--
-- For simulation/testability, PRIME_WIDTH is generic (default 16 for fast sim).
-- For real RSA-1024, set PRIME_WIDTH=512.
--
-- Note: The multiplications (p*q, (p-1)*(q-1)) are done combinationally
-- which is fine for simulation. For synthesis at large widths, replace with
-- a sequential multiplier.
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity RSA_KEYGEN is
  generic(
    PRIME_WIDTH : positive := 512;  -- Bit width of primes p, q
    NUM_WITNESSES : positive := 4  -- Miller-Rabin rounds
  );
  port(
    clk     : in  std_logic;
    rst     : in  std_logic;
    start   : in  std_logic;

    -- Seed for the PRNG (must be non-zero)
    seed    : in  unsigned(127 downto 0);
    load    : in  std_logic;

    -- Outputs
    o_done  : out std_logic;
    o_N     : out unsigned(2*PRIME_WIDTH-1 downto 0);  -- Public modulus
    o_e     : out unsigned(2*PRIME_WIDTH-1 downto 0);  -- Public exponent
    o_d     : out unsigned(2*PRIME_WIDTH-1 downto 0);  -- Private exponent
    o_valid : out std_logic                            -- '1' if key generation succeeded
  );
end entity;

architecture RTL of RSA_KEYGEN is

  constant KEY_WIDTH : positive := 2 * PRIME_WIDTH;

  -- Fixed public exponent (needs at least 17 bits, stored in KEY_WIDTH)
  constant E_VALUE : unsigned(KEY_WIDTH-1 downto 0) := to_unsigned(65537, KEY_WIDTH);

  -- =========================================================================
  -- Component declarations
  -- =========================================================================

  component RANDOM_GEN is
    generic(WIDTH : positive);
    port(
      clk    : in  std_logic;
      rst    : in  std_logic;
      seed   : in  unsigned(127 downto 0);
      load   : in  std_logic;
      start  : in  std_logic;
      o_done : out std_logic;
      o_rng  : out unsigned(WIDTH-1 downto 0)
    );
  end component;

  component MILLER_RABIN is
    generic(
      K             : positive;
      NUM_WITNESSES : positive
    );
    port(
      clk     : in  std_logic;
      rst     : in  std_logic;
      start   : in  std_logic;
      i_n     : in  unsigned(K-1 downto 0);
      o_done  : out std_logic;
      o_prime : out std_logic
    );
  end component;

  component EXT_GCD is
    generic(K : positive);
    port(
      clk     : in  std_logic;
      rst     : in  std_logic;
      start   : in  std_logic;
      i_e     : in  unsigned(K-1 downto 0);
      i_phi   : in  unsigned(K-1 downto 0);
      o_done  : out std_logic;
      o_valid : out std_logic;
      o_d     : out unsigned(K-1 downto 0)
    );
  end component;

  -- =========================================================================
  -- FSM
  -- =========================================================================
  type state_t is (
    IDLE,
    ST_GEN_P,          -- Request random number for p
    ST_GEN_P_WAIT,     -- Wait for PRNG
    ST_TEST_P,         -- Start Miller-Rabin on p candidate
    ST_TEST_P_WAIT,    -- Wait for primality result
    ST_GEN_Q,          -- Request random number for q
    ST_GEN_Q_WAIT,     -- Wait for PRNG
    ST_TEST_Q,         -- Start Miller-Rabin on q candidate
    ST_TEST_Q_WAIT,    -- Wait for primality result
    ST_COMPUTE_N,      -- N = p * q, phi = (p-1)*(q-1)
    ST_GCD_LAUNCH,     -- Start EXT_GCD for d = e^-1 mod phi
    ST_GCD_WAIT,       -- Wait for GCD result
    ST_OUTPUT_KEYS,    -- Latch outputs
    DONE_ST
  );
  signal state : state_t := IDLE;

  -- =========================================================================
  -- Internal signals
  -- =========================================================================

  -- PRNG interface
  signal rng_start : std_logic := '0';
  signal rng_done  : std_logic;
  signal rng_out   : unsigned(PRIME_WIDTH-1 downto 0);

  -- Miller-Rabin interface
  signal mr_start  : std_logic := '0';
  signal mr_input  : unsigned(PRIME_WIDTH-1 downto 0) := (others => '0');
  signal mr_done   : std_logic;
  signal mr_prime  : std_logic;

  -- EXT_GCD interface
  signal gcd_start : std_logic := '0';
  signal gcd_e     : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal gcd_phi   : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal gcd_done  : std_logic;
  signal gcd_valid : std_logic;
  signal gcd_d     : unsigned(KEY_WIDTH-1 downto 0);

  -- Stored primes
  signal p_reg : unsigned(PRIME_WIDTH-1 downto 0) := (others => '0');
  signal q_reg : unsigned(PRIME_WIDTH-1 downto 0) := (others => '0');

  -- Computed values
  signal n_reg   : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal phi_reg : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal d_reg   : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');

  -- Valid flag
  signal valid_reg : std_logic := '0';

begin

  -- =========================================================================
  -- Component instantiations
  -- =========================================================================

  RNG_INST : RANDOM_GEN
    generic map(WIDTH => PRIME_WIDTH)
    port map(
      clk    => clk,
      rst    => rst,
      seed   => seed,
      load   => load,
      start  => rng_start,
      o_done => rng_done,
      o_rng  => rng_out
    );

  MR_INST : MILLER_RABIN
    generic map(
      K             => PRIME_WIDTH,
      NUM_WITNESSES => NUM_WITNESSES
    )
    port map(
      clk     => clk,
      rst     => rst,
      start   => mr_start,
      i_n     => mr_input,
      o_done  => mr_done,
      o_prime => mr_prime
    );

  GCD_INST : EXT_GCD
    generic map(K => KEY_WIDTH)
    port map(
      clk     => clk,
      rst     => rst,
      start   => gcd_start,
      i_e     => gcd_e,
      i_phi   => gcd_phi,
      o_done  => gcd_done,
      o_valid => gcd_valid,
      o_d     => gcd_d
    );

  -- =========================================================================
  -- Main FSM
  -- =========================================================================
  process(clk, rst)
  begin
    if rst = '1' then
      state     <= IDLE;
      rng_start <= '0';
      mr_start  <= '0';
      gcd_start <= '0';
      mr_input  <= (others => '0');
      gcd_e     <= (others => '0');
      gcd_phi   <= (others => '0');
      p_reg     <= (others => '0');
      q_reg     <= (others => '0');
      n_reg     <= (others => '0');
      phi_reg   <= (others => '0');
      d_reg     <= (others => '0');
      valid_reg <= '0';
      o_done    <= '0';
      o_N       <= (others => '0');
      o_e       <= (others => '0');
      o_d       <= (others => '0');
      o_valid   <= '0';

    elsif rising_edge(clk) then
      rng_start <= '0';
      mr_start  <= '0';
      gcd_start <= '0';
      o_done    <= '0';

      case state is
        -- ================================================================
        when IDLE =>
          if start = '1' then
            state <= ST_GEN_P;
          end if;

        -- ================================================================
        -- Generate candidate for p
        -- ================================================================
        when ST_GEN_P =>
          rng_start <= '1';
          state     <= ST_GEN_P_WAIT;

        when ST_GEN_P_WAIT =>
          if rng_done = '1' then
            mr_input <= rng_out;
            mr_start <= '1';
            state    <= ST_TEST_P;
          end if;

        -- ================================================================
        -- Test p for primality
        -- ================================================================
        when ST_TEST_P =>
          state <= ST_TEST_P_WAIT;

        when ST_TEST_P_WAIT =>
          if mr_done = '1' then
            if mr_prime = '1' then
              -- p is prime, save it
              p_reg <= mr_input;
              state <= ST_GEN_Q;
            else
              -- Not prime, try another candidate
              state <= ST_GEN_P;
            end if;
          end if;

        -- ================================================================
        -- Generate candidate for q
        -- ================================================================
        when ST_GEN_Q =>
          rng_start <= '1';
          state     <= ST_GEN_Q_WAIT;

        when ST_GEN_Q_WAIT =>
          if rng_done = '1' then
            mr_input <= rng_out;
            mr_start <= '1';
            state    <= ST_TEST_Q;
          end if;

        -- ================================================================
        -- Test q for primality
        -- ================================================================
        when ST_TEST_Q =>
          state <= ST_TEST_Q_WAIT;

        when ST_TEST_Q_WAIT =>
          if mr_done = '1' then
            if mr_prime = '1' then
              -- q is prime, save it
              q_reg <= mr_input;
              -- Also ensure p /= q
              if mr_input = p_reg then
                -- Same as p, try again
                state <= ST_GEN_Q;
              else
                state <= ST_COMPUTE_N;
              end if;
            else
              -- Not prime, try another candidate
              state <= ST_GEN_Q;
            end if;
          end if;

        -- ================================================================
        -- Compute N = p*q and phi = (p-1)*(q-1)
        -- ================================================================
        when ST_COMPUTE_N =>
          -- p_reg and q_reg are PRIME_WIDTH bits, so p*q fits in 2*PRIME_WIDTH = KEY_WIDTH bits
          n_reg   <= p_reg * q_reg;
          phi_reg <= (p_reg - 1) * (q_reg - 1);
          state   <= ST_GCD_LAUNCH;

        -- ================================================================
        -- Compute d = e^(-1) mod phi
        -- ================================================================
        when ST_GCD_LAUNCH =>
          gcd_e     <= resize(E_VALUE, KEY_WIDTH);
          gcd_phi   <= phi_reg;
          gcd_start <= '1';
          state     <= ST_GCD_WAIT;

        when ST_GCD_WAIT =>
          if gcd_done = '1' then
            if gcd_valid = '1' then
              d_reg     <= gcd_d;
              valid_reg <= '1';
              state     <= ST_OUTPUT_KEYS;
            else
              -- gcd(e, phi) /= 1, retry with new q
              valid_reg <= '0';
              state     <= ST_GEN_Q;
            end if;
          end if;

        -- ================================================================
        -- Output the generated keys
        -- ================================================================
        when ST_OUTPUT_KEYS =>
          o_N     <= n_reg;
          o_e     <= E_VALUE;
          o_d     <= d_reg;
          o_valid <= valid_reg;
          state   <= DONE_ST;

        -- ================================================================
        when DONE_ST =>
          o_done <= '1';
          state  <= IDLE;

      end case;
    end if;
  end process;

end RTL;
