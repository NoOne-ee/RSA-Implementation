-- =============================================================================
-- MILLER_RABIN.vhd
-- Miller-Rabin Primality Tester
--
-- Tests whether an input number 'n' is probably prime using the Miller-Rabin
-- algorithm with a configurable number of witness rounds.
--
-- Algorithm:
--   Given odd n > 3, write n-1 = 2^s * d (d odd)
--   For each witness a:
--     x = a^d mod n
--     if x == 1 or x == n-1: continue (probably prime for this witness)
--     for r = 1 to s-1:
--       x = x^2 mod n
--       if x == n-1: continue outer (probably prime for this witness)
--     return COMPOSITE
--   return PROBABLY PRIME
--
-- This block reuses the MOD_MONTGOMERY_EXP component for modular exponentiation.
-- Witnesses are small fixed values: 2, 3, 5, 7 (sufficient for testing).
--
-- For simulation/small numbers, NUM_WITNESSES=4 gives high confidence.
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity MILLER_RABIN is
  generic(
    K             : positive := 32;   -- Bit width of the number to test
    NUM_WITNESSES : positive := 4     -- Number of Miller-Rabin rounds
  );
  port(
    clk       : in  std_logic;
    rst       : in  std_logic;
    start     : in  std_logic;
    i_n       : in  unsigned(K-1 downto 0);  -- Number to test (odd, > 3)
    o_done    : out std_logic;
    o_prime   : out std_logic  -- '1' = probably prime, '0' = composite
  );
end entity;

architecture RTL of MILLER_RABIN is

  -- MOD_MONTGOMERY_EXP component declaration
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

  -- FSM states
  type state_t is (
    IDLE,
    CHECK_TRIVIAL,        -- Check for n=2, n=3, even
    DECOMPOSE,            -- Compute s, d such that n-1 = 2^s * d (iterative)
    LOAD_WITNESS,         -- Select next witness value
    EXP_START,            -- Launch a^d mod n
    EXP_WAIT,             -- Wait for exponentiation result
    CHECK_INITIAL,        -- Check if x == 1 or x == n-1
    SQ_START,             -- Launch x^2 mod n (squaring loop)
    SQ_WAIT,              -- Wait for squaring result
    CHECK_SQUARE,         -- Check if x == n-1
    COMPOSITE,            -- Determined composite
    PRIME,                -- Determined probably prime
    DONE_ST
  );
  signal state : state_t := IDLE;

  -- Registered inputs
  signal n_reg   : unsigned(K-1 downto 0) := (others => '0');
  signal nm1     : unsigned(K-1 downto 0) := (others => '0');  -- n - 1
  signal d_reg   : unsigned(K-1 downto 0) := (others => '0');  -- odd part of n-1
  signal s_reg   : integer range 0 to K   := 0;                -- power of 2

  -- Witness table (small primes)
  type witness_array_t is array (0 to 3) of unsigned(K-1 downto 0);
  signal witnesses : witness_array_t;

  -- Iteration counters
  signal wit_idx  : integer range 0 to NUM_WITNESSES-1 := 0;
  signal r_cnt    : integer range 0 to K := 0;

  -- Current computation values
  signal x_reg   : unsigned(K-1 downto 0) := (others => '0');

  -- Montgomery exponentiation interface
  signal exp_start : std_logic := '0';
  signal exp_base  : unsigned(K-1 downto 0) := (others => '0');
  signal exp_exp   : unsigned(K-1 downto 0) := (others => '0');
  signal exp_mod   : unsigned(K-1 downto 0) := (others => '0');
  signal exp_done  : std_logic;
  signal exp_result: unsigned(K-1 downto 0);

  -- Result register
  signal result_reg : std_logic := '0';

begin

  -- Instantiate Montgomery exponentiation (exponent same width as base)
  EXP_UNIT : MOD_MONTGOMERY_EXP
    generic map(
      K     => K,
      K_EXP => K
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

  -- Main FSM
  process(clk, rst)
  begin
    if rst = '1' then
      state      <= IDLE;
      n_reg      <= (others => '0');
      nm1        <= (others => '0');
      d_reg      <= (others => '0');
      s_reg      <= 0;
      wit_idx    <= 0;
      r_cnt      <= 0;
      x_reg      <= (others => '0');
      exp_start  <= '0';
      exp_base   <= (others => '0');
      exp_exp    <= (others => '0');
      exp_mod    <= (others => '0');
      result_reg <= '0';
      o_done     <= '0';
      o_prime    <= '0';

    elsif rising_edge(clk) then
      exp_start <= '0';
      o_done    <= '0';

      case state is
        -- ================================================================
        when IDLE =>
          if start = '1' then
            n_reg <= i_n;
            nm1   <= i_n - 1;
            -- Initialize witnesses as K-bit values
            witnesses(0) <= to_unsigned(2, K);
            witnesses(1) <= to_unsigned(3, K);
            witnesses(2) <= to_unsigned(5, K);
            witnesses(3) <= to_unsigned(7, K);
            state <= CHECK_TRIVIAL;
          end if;

        -- ================================================================
        -- Handle trivial cases: n=2,3 are prime; even numbers are composite
        when CHECK_TRIVIAL =>
          if n_reg = to_unsigned(2, K) or n_reg = to_unsigned(3, K) then
            result_reg <= '1';
            state      <= DONE_ST;
          elsif n_reg(0) = '0' or n_reg < to_unsigned(4, K) then
            -- Even or less than 2
            result_reg <= '0';
            state      <= DONE_ST;
          else
            -- Initialize for decomposition: d = n-1, s = 0
            d_reg <= nm1;
            s_reg <= 0;
            state <= DECOMPOSE;
          end if;

        -- ================================================================
        -- Decompose n-1 = 2^s * d (one shift per clock until d is odd)
        when DECOMPOSE =>
          if d_reg(0) = '1' then
            -- d is now odd, decomposition complete
            wit_idx <= 0;
            state   <= LOAD_WITNESS;
          else
            -- Shift right, increment s
            d_reg <= '0' & d_reg(K-1 downto 1);
            s_reg <= s_reg + 1;
          end if;

        -- ================================================================
        -- Load next witness
        when LOAD_WITNESS =>
          -- Skip witness if >= n-1 (for small n)
          if witnesses(wit_idx) >= nm1 then
            -- All remaining witnesses too large, consider prime
            result_reg <= '1';
            state      <= DONE_ST;
          else
            -- Compute a^d mod n
            exp_base  <= witnesses(wit_idx);
            exp_exp   <= d_reg;
            exp_mod   <= n_reg;
            exp_start <= '1';
            state     <= EXP_START;
          end if;

        -- ================================================================
        when EXP_START =>
          state <= EXP_WAIT;

        -- ================================================================
        when EXP_WAIT =>
          if exp_done = '1' then
            x_reg <= exp_result;
            state <= CHECK_INITIAL;
          end if;

        -- ================================================================
        -- Check if x == 1 or x == n-1
        when CHECK_INITIAL =>
          if x_reg = to_unsigned(1, K) or x_reg = nm1 then
            -- This witness says probably prime, try next
            if wit_idx = NUM_WITNESSES - 1 then
              result_reg <= '1';
              state      <= DONE_ST;
            else
              wit_idx <= wit_idx + 1;
              state   <= LOAD_WITNESS;
            end if;
          else
            -- Start squaring loop
            r_cnt <= 1;
            state <= SQ_START;
          end if;

        -- ================================================================
        -- Compute x = x^2 mod n
        when SQ_START =>
          if r_cnt >= s_reg then
            -- Exhausted all squarings without finding n-1 → composite
            state <= COMPOSITE;
          else
            exp_base  <= x_reg;
            exp_exp   <= to_unsigned(2, K);
            exp_mod   <= n_reg;
            exp_start <= '1';
            state     <= SQ_WAIT;
          end if;

        -- ================================================================
        when SQ_WAIT =>
          if exp_done = '1' then
            x_reg <= exp_result;
            state <= CHECK_SQUARE;
          end if;

        -- ================================================================
        -- Check if x == n-1 after squaring
        when CHECK_SQUARE =>
          if x_reg = nm1 then
            -- This witness passes, try next
            if wit_idx = NUM_WITNESSES - 1 then
              result_reg <= '1';
              state      <= DONE_ST;
            else
              wit_idx <= wit_idx + 1;
              state   <= LOAD_WITNESS;
            end if;
          elsif x_reg = to_unsigned(1, K) then
            -- x == 1 means composite (non-trivial sqrt of 1)
            state <= COMPOSITE;
          else
            r_cnt <= r_cnt + 1;
            state <= SQ_START;
          end if;

        -- ================================================================
        when COMPOSITE =>
          result_reg <= '0';
          state      <= DONE_ST;

        -- ================================================================
        when PRIME =>
          result_reg <= '1';
          state      <= DONE_ST;

        -- ================================================================
        when DONE_ST =>
          o_prime <= result_reg;
          o_done  <= '1';
          state   <= IDLE;

      end case;
    end if;
  end process;

end RTL;
