-- =============================================================================
-- RSA_SYSTEM.vhd
-- Complete RSA System: Key Generation + Encryption + Decryption
--
-- This top-level block connects RSA_KEYGEN with a modified RSA encryption/
-- decryption engine that supports full-width exponents.
--
-- Architecture:
--   1. RSA_KEYGEN generates (N, e, d) from a PRNG seed
--   2. For encryption:  ciphertext = message^e mod N
--   3. For decryption:  plaintext  = ciphertext^d mod N
--
-- The system uses PRIME_WIDTH-bit primes, giving KEY_WIDTH = 2*PRIME_WIDTH bit
-- modulus and exponents. For real RSA-1024, set PRIME_WIDTH=512.
--
-- Interface:
--   Phase 1 - Key Generation:
--     1. Load seed (seed + load pulse)
--     2. Assert gen_keys to start key generation
--     3. Wait for keys_ready
--
--   Phase 2 - Encrypt/Decrypt:
--     1. Provide message on i_message
--     2. Set mode: '0' = encrypt (uses e), '1' = decrypt (uses d)
--     3. Assert start
--     4. Wait for o_done, read o_result
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity RSA_SYSTEM is
  generic(
    PRIME_WIDTH   : positive := 16;   -- 16 for testing, 512 for real RSA-1024
    NUM_WITNESSES : positive := 4
  );
  port(
    clk         : in  std_logic;
    rst         : in  std_logic;

    -- Key generation interface
    seed        : in  unsigned(127 downto 0);
    load        : in  std_logic;
    gen_keys    : in  std_logic;           -- Start key generation
    keys_ready  : out std_logic;           -- Keys are valid

    -- Encryption/Decryption interface
    i_message   : in  unsigned(2*PRIME_WIDTH-1 downto 0);
    mode        : in  std_logic;           -- '0' = encrypt (use e), '1' = decrypt (use d)
    start       : in  std_logic;
    o_done      : out std_logic;
    o_result    : out unsigned(2*PRIME_WIDTH-1 downto 0);

    -- Key outputs (for inspection/debugging)
    o_N         : out unsigned(2*PRIME_WIDTH-1 downto 0);
    o_e         : out unsigned(2*PRIME_WIDTH-1 downto 0);
    o_d         : out unsigned(2*PRIME_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RSA_SYSTEM is

  constant KEY_WIDTH : positive := 2 * PRIME_WIDTH;

  -- =========================================================================
  -- Component declarations
  -- =========================================================================

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

  -- =========================================================================
  -- FSM for encrypt/decrypt
  -- =========================================================================
  type crypto_state_t is (
    IDLE,
    ST_REDUCE,
    ST_EXP_LAUNCH,
    ST_EXP_WAIT,
    ST_LATCH,
    ST_DONE
  );
  signal crypto_state : crypto_state_t := IDLE;

  -- =========================================================================
  -- Signals
  -- =========================================================================

  -- Key generation
  signal kg_done    : std_logic;
  signal kg_valid   : std_logic;
  signal n_reg      : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal e_reg      : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal d_reg      : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal keys_valid : std_logic := '0';

  -- Modular exponentiation for encrypt/decrypt
  signal exp_go     : std_logic := '0';
  signal exp_base   : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal exp_exp    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal exp_mod    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal exp_done   : std_logic;
  signal exp_result : unsigned(KEY_WIDTH-1 downto 0);

  -- Internal
  signal msg_reduced : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');

begin

  -- =========================================================================
  -- Key Generation Block
  -- =========================================================================
  KEYGEN_INST : RSA_KEYGEN
    generic map(
      PRIME_WIDTH   => PRIME_WIDTH,
      NUM_WITNESSES => NUM_WITNESSES
    )
    port map(
      clk     => clk,
      rst     => rst,
      start   => gen_keys,
      seed    => seed,
      load    => load,
      o_done  => kg_done,
      o_N     => o_N,
      o_e     => o_e,
      o_d     => o_d,
      o_valid => kg_valid
    );

  -- =========================================================================
  -- Montgomery Exponentiation for Encrypt/Decrypt
  -- Uses KEY_WIDTH-bit exponent (supports both e and d)
  -- =========================================================================
  EXP_INST : MOD_MONTGOMERY_EXP
    generic map(
      K     => KEY_WIDTH,
      K_EXP => KEY_WIDTH
    )
    port map(
      clk    => clk,
      rst    => rst,
      start  => exp_go,
      i_X    => exp_base,
      i_e    => exp_exp,
      i_Mod  => exp_mod,
      o_done => exp_done,
      o_Z    => exp_result
    );

  -- =========================================================================
  -- Key latch + outputs
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        n_reg      <= (others => '0');
        e_reg      <= (others => '0');
        d_reg      <= (others => '0');
        keys_valid <= '0';
      elsif kg_done = '1' and kg_valid = '1' then
        n_reg      <= o_N;
        e_reg      <= o_e;
        d_reg      <= o_d;
        keys_valid <= '1';
      end if;
    end if;
  end process;

  keys_ready <= keys_valid;

  -- =========================================================================
  -- Encrypt/Decrypt FSM
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        crypto_state <= IDLE;
        exp_go       <= '0';
        exp_base     <= (others => '0');
        exp_exp      <= (others => '0');
        exp_mod      <= (others => '0');
        msg_reduced  <= (others => '0');
        o_done       <= '0';
        o_result     <= (others => '0');
      else
        exp_go <= '0';
        o_done <= '0';

        case crypto_state is
          -- ================================================================
          when IDLE =>
            if start = '1' and keys_valid = '1' then
              -- Reduce message mod N
              if n_reg /= 0 then
                msg_reduced <= resize(i_message mod n_reg, KEY_WIDTH);
              else
                msg_reduced <= i_message;
              end if;
              crypto_state <= ST_REDUCE;
            end if;

          -- ================================================================
          when ST_REDUCE =>
            exp_base <= msg_reduced;
            exp_mod  <= n_reg;
            -- Select exponent based on mode
            if mode = '0' then
              exp_exp <= e_reg;   -- Encrypt with e
            else
              exp_exp <= d_reg;   -- Decrypt with d
            end if;
            exp_go       <= '1';
            crypto_state <= ST_EXP_LAUNCH;

          -- ================================================================
          when ST_EXP_LAUNCH =>
            crypto_state <= ST_EXP_WAIT;

          -- ================================================================
          when ST_EXP_WAIT =>
            if exp_done = '1' then
              crypto_state <= ST_LATCH;
            end if;

          -- ================================================================
          when ST_LATCH =>
            o_result     <= exp_result;
            crypto_state <= ST_DONE;

          -- ================================================================
          when ST_DONE =>
            o_done       <= '1';
            crypto_state <= IDLE;

        end case;
      end if;
    end if;
  end process;

end RTL;
