-- =============================================================================
-- TB_MILLER_RABIN.vhd
-- Testbench for MILLER_RABIN primality tester.
--
-- For each candidate, expect o_prime = '1' if known prime, '0' otherwise.
-- Internally MILLER_RABIN instantiates MOD_MONTGOMERY_EXP, so this also
-- exercises the integration of the two.
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TB_MILLER_RABIN is
end entity;

architecture sim of TB_MILLER_RABIN is

  constant K          : positive := 16;
  constant NUM_W      : positive := 4;
  constant CLK_PERIOD : time     := 10 ns;

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal start   : std_logic := '0';
  signal i_n     : unsigned(K-1 downto 0) := (others => '0');
  signal o_done  : std_logic;
  signal o_prime : std_logic;

  signal pass_cnt : integer := 0;
  signal fail_cnt : integer := 0;

begin

  clk <= not clk after CLK_PERIOD/2;

  DUT : entity work.MILLER_RABIN
    generic map(K => K, NUM_WITNESSES => NUM_W)
    port map(
      clk     => clk,
      rst     => rst,
      start   => start,
      i_n     => i_n,
      o_done  => o_done,
      o_prime => o_prime
    );

  process

    procedure wait_clk(n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    procedure run_test(n : integer; exp_prime : std_logic) is
    begin
      i_n <= to_unsigned(n, K);
      wait_clk(1);
      start <= '1'; wait_clk(1); start <= '0';

      while o_done /= '1' loop
        wait until rising_edge(clk);
      end loop;
      wait_clk(1);

      if o_prime = exp_prime then
        if exp_prime = '1' then
          report "[PASS] " & integer'image(n) & " correctly reported PRIME"
            severity note;
        else
          report "[PASS] " & integer'image(n) & " correctly reported COMPOSITE"
            severity note;
        end if;
        pass_cnt <= pass_cnt + 1;
      else
        report "[FAIL] " & integer'image(n) & " expected="
             & std_logic'image(exp_prime) & " got=" & std_logic'image(o_prime)
          severity error;
        fail_cnt <= fail_cnt + 1;
      end if;
      wait_clk(2);
    end procedure;

  begin
    rst <= '1'; wait_clk(5); rst <= '0'; wait_clk(2);

    -- Small primes
    run_test(  7, '1');
    run_test( 11, '1');
    run_test( 13, '1');
    run_test( 17, '1');
    run_test( 23, '1');
    run_test( 97, '1');
    run_test(101, '1');
    run_test(251, '1');
    run_test(257, '1');

    -- Composites
    run_test(  9, '0');   -- 3*3
    run_test( 15, '0');   -- 3*5
    run_test( 21, '0');   -- 3*7
    run_test( 25, '0');   -- 5*5
    run_test( 49, '0');   -- 7*7
    run_test( 51, '0');   -- 3*17

    wait_clk(5);
    report "TB_MILLER_RABIN: pass=" & integer'image(pass_cnt)
         & " fail=" & integer'image(fail_cnt) severity note;

    if fail_cnt = 0 then
      report "ALL TESTS PASSED" severity note;
    else
      report "SOME TESTS FAILED" severity error;
    end if;

    wait for 50 ns;
    assert false report "Simulation finished" severity failure;
  end process;

end architecture;
