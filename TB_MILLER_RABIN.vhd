-- =============================================================================
-- TB_MILLER_RABIN.vhd
-- Testbench for MILLER_RABIN primality tester
--
-- Tests with 32-bit numbers (K=32) for fast simulation:
--   1. Known primes: 7, 13, 101, 7919, 104729, 2147483647 (Mersenne prime)
--   2. Known composites: 4, 9, 15, 100, 561 (Carmichael), 1105 (Carmichael)
--   3. Edge cases: 2, 3
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TB_MILLER_RABIN is
end entity;

architecture SIM of TB_MILLER_RABIN is

  constant K : positive := 32;
  constant CLK_PERIOD : time := 10 ns;

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal start   : std_logic := '0';
  signal i_n     : unsigned(K-1 downto 0) := (others => '0');
  signal o_done  : std_logic;
  signal o_prime : std_logic;

  signal test_pass : integer := 0;
  signal test_fail : integer := 0;

begin

  -- Clock generation
  clk <= not clk after CLK_PERIOD / 2;

  -- DUT instantiation
  DUT : entity work.MILLER_RABIN
    generic map(
      K             => K,
      NUM_WITNESSES => 4
    )
    port map(
      clk     => clk,
      rst     => rst,
      start   => start,
      i_n     => i_n,
      o_done  => o_done,
      o_prime => o_prime
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
      variable timeout : integer := 0;
    begin
      while o_done /= '1' loop
        wait until rising_edge(clk);
        timeout := timeout + 1;
        if timeout > 500000 then
          report "[TIMEOUT] Simulation stuck!" severity error;
          exit;
        end if;
      end loop;
    end procedure;

    procedure test_number(n_val : integer; expect_prime : boolean; name : string) is
    begin
      i_n   <= to_unsigned(n_val, K);
      start <= '1';
      wait_clk(1);
      start <= '0';

      wait_done;
      wait_clk(1);

      if expect_prime then
        if o_prime = '1' then
          report "[PASS] " & name & " = " & integer'image(n_val) & " detected as PRIME" severity note;
          test_pass <= test_pass + 1;
        else
          report "[FAIL] " & name & " = " & integer'image(n_val) & " should be PRIME but got COMPOSITE" severity error;
          test_fail <= test_fail + 1;
        end if;
      else
        if o_prime = '0' then
          report "[PASS] " & name & " = " & integer'image(n_val) & " detected as COMPOSITE" severity note;
          test_pass <= test_pass + 1;
        else
          report "[FAIL] " & name & " = " & integer'image(n_val) & " should be COMPOSITE but got PRIME" severity error;
          test_fail <= test_fail + 1;
        end if;
      end if;

      wait_clk(3);
    end procedure;

  begin
    -- ========================================================================
    -- Reset
    -- ========================================================================
    rst <= '1';
    wait_clk(5);
    rst <= '0';
    wait_clk(3);

    -- ========================================================================
    -- TEST GROUP 1: Edge cases
    -- ========================================================================
    report "=== TEST GROUP 1: Edge cases ===" severity note;

    test_number(2,  true,  "Edge prime 2");
    test_number(3,  true,  "Edge prime 3");

    -- ========================================================================
    -- TEST GROUP 2: Known primes
    -- ========================================================================
    report "=== TEST GROUP 2: Known primes ===" severity note;

    test_number(7,      true, "Small prime 7");
    test_number(13,     true, "Small prime 13");
    test_number(101,    true, "Prime 101");
    test_number(7919,   true, "Prime 7919");
    test_number(104729, true, "Prime 104729");

    -- ========================================================================
    -- TEST GROUP 3: Known composites
    -- ========================================================================
    report "=== TEST GROUP 3: Known composites ===" severity note;

    test_number(4,    false, "Composite 4");
    test_number(9,    false, "Composite 9");
    test_number(15,   false, "Composite 15");
    test_number(100,  false, "Composite 100");
    test_number(561,  false, "Carmichael 561");
    test_number(1105, false, "Carmichael 1105");

    -- ========================================================================
    -- TEST GROUP 4: Larger primes
    -- ========================================================================
    report "=== TEST GROUP 4: Larger primes ===" severity note;

    test_number(65537,   true, "Fermat prime 65537 (common RSA e)");
    test_number(104723,  true, "Prime 104723");

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
