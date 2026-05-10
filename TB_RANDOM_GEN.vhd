-- =============================================================================
-- TB_RANDOM_GEN.vhd
-- Testbench for RANDOM_GEN (LFSR-based PRNG)
--
-- Tests:
--   1. Seed loading and basic generation
--   2. MSB=1 and LSB=1 constraints are enforced
--   3. Multiple consecutive outputs are different (randomness check)
--   4. Different seeds produce different sequences
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TB_RANDOM_GEN is
end entity;

architecture SIM of TB_RANDOM_GEN is

  constant WIDTH : positive := 512;
  constant CLK_PERIOD : time := 10 ns;

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal seed   : unsigned(127 downto 0) := (others => '0');
  signal load   : std_logic := '0';
  signal start  : std_logic := '0';
  signal o_done : std_logic;
  signal o_rng  : unsigned(WIDTH-1 downto 0);

  -- Storage for checking uniqueness
  signal result1 : unsigned(WIDTH-1 downto 0) := (others => '0');
  signal result2 : unsigned(WIDTH-1 downto 0) := (others => '0');
  signal result3 : unsigned(WIDTH-1 downto 0) := (others => '0');

  signal test_pass : integer := 0;
  signal test_fail : integer := 0;

begin

  -- Clock generation
  clk <= not clk after CLK_PERIOD / 2;

  -- DUT instantiation
  DUT : entity work.RANDOM_GEN
    generic map(WIDTH => WIDTH)
    port map(
      clk    => clk,
      rst    => rst,
      seed   => seed,
      load   => load,
      start  => start,
      o_done => o_done,
      o_rng  => o_rng
    );

  -- Stimulus process
  STIM : process
    procedure wait_clk(n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    procedure wait_done is
    begin
      while o_done /= '1' loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
      if cond then
        report "[PASS] " & msg severity note;
        test_pass <= test_pass + 1;
      else
        report "[FAIL] " & msg severity error;
        test_fail <= test_fail + 1;
      end if;
    end procedure;

  begin
    -- ========================================================================
    -- Reset
    -- ========================================================================
    rst <= '1';
    wait_clk(3);
    rst <= '0';
    wait_clk(2);

    -- ========================================================================
    -- TEST 1: Load seed and generate first number
    -- ========================================================================
    report "=== TEST 1: Basic generation with seed ===" severity note;

    seed <= x"DEADBEEFCAFEBABE1234567890ABCDEF";
    load <= '1';
    wait_clk(1);
    load <= '0';
    wait_clk(1);

    -- Request generation
    start <= '1';
    wait_clk(1);
    start <= '0';

    -- Wait for done
    wait_done;
    wait_clk(1);

    result1 <= o_rng;

    check(o_rng(WIDTH-1) = '1', "TEST 1: MSB is 1 (full bit-length)");
    check(o_rng(0) = '1',       "TEST 1: LSB is 1 (odd number)");
    check(o_rng /= 0,           "TEST 1: Output is non-zero");

    report "  TEST 1: Generated a valid random number" severity note;

    wait_clk(3);

    -- ========================================================================
    -- TEST 2: Generate second number (should differ from first)
    -- ========================================================================
    report "=== TEST 2: Second generation (uniqueness) ===" severity note;

    start <= '1';
    wait_clk(1);
    start <= '0';

    wait_done;
    wait_clk(1);

    result2 <= o_rng;

    check(o_rng(WIDTH-1) = '1', "TEST 2: MSB is 1");
    check(o_rng(0) = '1',       "TEST 2: LSB is 1");
    check(o_rng /= result1,     "TEST 2: Different from first output");

    report "  TEST 2: Generated a unique random number" severity note;

    wait_clk(3);

    -- ========================================================================
    -- TEST 3: Third generation (all three should be unique)
    -- ========================================================================
    report "=== TEST 3: Third generation (all unique) ===" severity note;

    start <= '1';
    wait_clk(1);
    start <= '0';

    wait_done;
    wait_clk(1);

    result3 <= o_rng;

    check(o_rng(WIDTH-1) = '1', "TEST 3: MSB is 1");
    check(o_rng(0) = '1',       "TEST 3: LSB is 1");
    check(o_rng /= result1,     "TEST 3: Different from first");
    check(o_rng /= result2,     "TEST 3: Different from second");

    report "  TEST 3: All three outputs are unique" severity note;

    wait_clk(3);

    -- ========================================================================
    -- TEST 4: Different seed produces different sequence
    -- ========================================================================
    report "=== TEST 4: Different seed ===" severity note;

    -- Load a new seed
    seed <= x"0123456789ABCDEF_FEDCBA9876543210";
    load <= '1';
    wait_clk(1);
    load <= '0';
    wait_clk(1);

    start <= '1';
    wait_clk(1);
    start <= '0';

    wait_done;
    wait_clk(1);

    check(o_rng(WIDTH-1) = '1', "TEST 4: MSB is 1 (new seed)");
    check(o_rng(0) = '1',       "TEST 4: LSB is 1 (new seed)");
    check(o_rng /= result1,     "TEST 4: Different from seed1 result1");

    report "  TEST 4: New seed produces different output" severity note;

    wait_clk(5);

    -- ========================================================================
    -- Summary
    -- ========================================================================
    report "=====================================" severity note;
    report "  TESTS PASSED: " & integer'image(test_pass) severity note;
    report "  TESTS FAILED: " & integer'image(test_fail) severity note;
    report "=====================================" severity note;

    if test_fail = 0 then
      report "ALL TESTS PASSED!" severity note;
    else
      report "SOME TESTS FAILED!" severity error;
    end if;

    -- End simulation
    wait for 100 ns;
    assert false report "Simulation finished" severity failure;
  end process;

end SIM;
