-- =============================================================================
-- RSA_SYSTEM.vhd
-- Complete RSA System: Key Generation + Encrypt/Decrypt
--
-- This is the "top-of-top" block: the user only needs to provide a message.
-- The system generates its own (N, e, d) key pair at runtime using
-- RSA_KEYGEN, then encrypts or decrypts the message using
-- MOD_MONTGOMERY_EXP directly with the generated keys.
--
-- Typical usage:
--   1. Pulse 'load' with 'seed' valid to seed the internal PRNG.
--   2. Pulse 'gen_keys'. Wait for 'keys_ready' = '1'.
--   3. Drive i_message + mode ('0' encrypt, '1' decrypt), pulse 'start'.
--      Wait for 'o_done' = '1' and read 'o_result'.
--   4. Subsequent messages can reuse the same key pair; no need to regenerate
--      unless 'gen_keys' is pulsed again.
--
-- The generated keys are also exposed on o_N, o_e, o_d for observation.
--
-- Generics:
--   PRIME_WIDTH  : bit-width of primes p, q   (default 16 for fast sim)
--   NUM_WITNESSES: Miller-Rabin rounds        (default 4)
--   KEY_WIDTH   == 2 * PRIME_WIDTH            (derived; modulus / datapath width)
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity RSA_SYSTEM is
  generic(
    PRIME_WIDTH   : positive := 16;
    NUM_WITNESSES : positive := 4
  );
  port(
    clk        : in  std_logic;
    rst        : in  std_logic;

    -- Key-generation interface
    seed       : in  unsigned(127 downto 0);  -- PRNG seed (must be non-zero)
    load       : in  std_logic;               -- load seed pulse
    gen_keys   : in  std_logic;               -- pulse to (re)generate a key pair
    keys_ready : out std_logic;               -- '1' once a valid key pair is available

    -- Encrypt/decrypt interface
    i_message  : in  unsigned(2*PRIME_WIDTH-1 downto 0);
    mode       : in  std_logic;               -- '0' = encrypt (use e), '1' = decrypt (use d)
    start      : in  std_logic;               -- pulse to begin one operation
    o_done     : out std_logic;
    o_result   : out unsigned(2*PRIME_WIDTH-1 downto 0);

    -- Key observation (optional, for testbench / debug)
    o_N        : out unsigned(2*PRIME_WIDTH-1 downto 0);
    o_e        : out unsigned(2*PRIME_WIDTH-1 downto 0);
    o_d        : out unsigned(2*PRIME_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RSA_SYSTEM is

  constant KEY_WIDTH : positive := 2 * PRIME_WIDTH;

  -- -----------------------------------------------------------------
  -- Key generator
  -- -----------------------------------------------------------------
  component RSA_KEYGEN is
    generic(
      PRIME_WIDTH   : positive;
      NUM_WITNESSES : positive
    );
    port(
      clk     : in  std_logic;
      rst     : in  std_logic;
      start   : in  std_logic;
      seed    : in  unsigned(127 downto 0);
      load    : in  std_logic;
      o_done  : out std_logic;
      o_N     : out unsigned(2*PRIME_WIDTH-1 downto 0);
      o_e     : out unsigned(2*PRIME_WIDTH-1 downto 0);
      o_d     : out unsigned(2*PRIME_WIDTH-1 downto 0);
      o_valid : out std_logic
    );
  end component;

  -- -----------------------------------------------------------------
  -- Modular exponentiation engine (Montgomery-based)
  -- -----------------------------------------------------------------
  component MOD_MONTGOMERY_EXP is
    generic(
      K     : positive;
      K_EXP : positive
    );
    port(
      clk    : in  std_logic;
      rst    : in  std_logic;
      start  : in  std_logic;
      i_X    : in  unsigned(K-1     downto 0);
      i_e    : in  unsigned(K_EXP-1 downto 0);
      i_Mod  : in  unsigned(K-1     downto 0);
      o_done : out std_logic;
      o_Z    : out unsigned(K-1 downto 0)
    );
  end component;

  -- Keygen interface
  signal kg_start   : std_logic := '0';
  signal kg_done    : std_logic;
  signal kg_N       : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_e       : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_d       : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_valid   : std_logic;

  -- Latched key pair
  signal N_reg      : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal e_reg      : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal d_reg      : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal have_keys  : std_logic := '0';

  -- Modexp interface
  signal exp_start  : std_logic := '0';
  signal exp_done   : std_logic;
  signal exp_base   : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal exp_exp    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal exp_mod    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal exp_result : unsigned(KEY_WIDTH-1 downto 0);

  -- Master FSM
  type state_t is (
    S_IDLE,           -- No keys yet, or ready but idle
    S_KEYGEN_WAIT,    -- Key generation in progress
    S_READY,          -- Keys valid; waiting for start or another gen_keys
    S_REDUCE,         -- Compute message mod N, latch exponent
    S_EXP_LAUNCH,     -- Pulse start to MOD_MONTGOMERY_EXP
    S_EXP_WAIT,       -- Wait for modexp to finish
    S_OUTPUT          -- Drive o_done + o_result for one cycle
  );
  signal state : state_t := S_IDLE;

begin

  -- -----------------------------------------------------------------
  -- Component instantiations
  -- -----------------------------------------------------------------
  U_KEYGEN : RSA_KEYGEN
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

  U_EXP : MOD_MONTGOMERY_EXP
    generic map(
      K     => KEY_WIDTH,
      K_EXP => KEY_WIDTH
    )
    port map(
      clk    => clk,
      rst    => rst,
      start  => exp_start,
      i_X    => exp_base,
      i_e    => exp_exp,
      i_Mod  => exp_mod,
      o_done => exp_done,
      o_Z    => exp_result
    );

  -- Expose current keys
  o_N <= N_reg;
  o_e <= e_reg;
  o_d <= d_reg;

  keys_ready <= have_keys;

  -- -----------------------------------------------------------------
  -- Master FSM
  -- -----------------------------------------------------------------
  process(clk, rst)
  begin
    if rst = '1' then
      state     <= S_IDLE;
      kg_start  <= '0';
      exp_start <= '0';
      exp_base  <= (others => '0');
      exp_exp   <= (others => '0');
      exp_mod   <= (others => '0');
      N_reg     <= (others => '0');
      e_reg     <= (others => '0');
      d_reg     <= (others => '0');
      have_keys <= '0';
      o_done    <= '0';
      o_result  <= (others => '0');

    elsif rising_edge(clk) then
      -- Default: single-cycle pulses
      kg_start  <= '0';
      exp_start <= '0';
      o_done    <= '0';

      case state is
        -- --------------------------------------------------------
        when S_IDLE =>
          if gen_keys = '1' then
            kg_start  <= '1';
            have_keys <= '0';
            state     <= S_KEYGEN_WAIT;
          end if;

        -- --------------------------------------------------------
        when S_KEYGEN_WAIT =>
          if kg_done = '1' then
            if kg_valid = '1' then
              N_reg     <= kg_N;
              e_reg     <= kg_e;
              d_reg     <= kg_d;
              have_keys <= '1';
              state     <= S_READY;
            else
              -- Key generation failed; retry automatically.
              kg_start <= '1';
              state    <= S_KEYGEN_WAIT;
            end if;
          end if;

        -- --------------------------------------------------------
        when S_READY =>
          if gen_keys = '1' then
            -- User requested a fresh key pair.
            have_keys <= '0';
            kg_start  <= '1';
            state     <= S_KEYGEN_WAIT;
          elsif start = '1' then
            state <= S_REDUCE;
          end if;

        -- --------------------------------------------------------
        -- Reduce message mod N and select exponent based on mode.
        when S_REDUCE =>
          if N_reg /= 0 then
            exp_base <= resize(i_message mod N_reg, KEY_WIDTH);
          else
            exp_base <= i_message;
          end if;
          exp_mod <= N_reg;
          if mode = '1' then
            exp_exp <= d_reg;   -- decrypt
          else
            exp_exp <= e_reg;   -- encrypt
          end if;
          state <= S_EXP_LAUNCH;

        -- --------------------------------------------------------
        when S_EXP_LAUNCH =>
          exp_start <= '1';
          state     <= S_EXP_WAIT;

        -- --------------------------------------------------------
        when S_EXP_WAIT =>
          if exp_done = '1' then
            o_result <= exp_result;
            state    <= S_OUTPUT;
          end if;

        -- --------------------------------------------------------
        when S_OUTPUT =>
          o_done <= '1';
          state  <= S_READY;

      end case;
    end if;
  end process;

end RTL;
