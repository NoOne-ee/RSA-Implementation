-- =============================================================================
-- TB_MONTGOMERY_MULT.vhd
-- Testbench for MONTGOMERY_MULT.
-- Computes MonPro(X, Y, M) = X*Y*R^-1 mod M  with R = 2^K.
-- Expected values were precomputed (Python).
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TB_MONTGOMERY_MULT is
end entity;

architecture sim of TB_MONTGOMERY_MULT is

  constant K          : positive := 8;
  constant CLK_PERIOD : time     := 10 ns;

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal start  : std_logic := '0';
  signal i_X    : unsigned(K-1 downto 0) := (others => '0');
  signal i_Y    : unsigned(K-1 downto 0) := (others => '0');
  signal i_M    : unsigned(K-1 downto 0) := (others => '0');
  signal o_done : std_logic;
  signal o_Z    : unsigned(K-1 downto 0);

  signal pass_cnt : integer := 0;
  signal fail_cnt : integer := 0;

begin

  clk <= not clk after CLK_PERIOD/2;

  DUT : entity work.MONTGOMERY_MULT
    generic map(K => K)
    port map(clk, rst, start, i_X, i_Y, i_M, o_done, o_Z);

  process
    procedure wait_clk(n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    procedure run_test(x, y, m, exp : integer) is
    begin
      i_X <= to_unsigned(x, K);
      i_Y <= to_unsigned(y, K);
      i_M <= to_unsigned(m, K);
      wait_clk(1);
      start <= '1'; wait_clk(1); start <= '0';

      while o_done /= '1' loop
        wait until rising_edge(clk);
      end loop;
      wait_clk(1);

      if to_integer(o_Z) = exp then
        report "[PASS] MonPro(" & integer'image(x) & "," & integer'image(y)
             & "," & integer'image(m) & ") = " & integer'image(exp)
          severity note;
        pass_cnt <= pass_cnt + 1;
      else
        report "[FAIL] MonPro(" & integer'image(x) & "," & integer'image(y)
             & "," & integer'image(m) & ") expected="
             & integer'image(exp) & " got=" & integer'image(to_integer(o_Z))
          severity error;
        fail_cnt <= fail_cnt + 1;
      end if;
      wait_clk(2);
    end procedure;

  begin
    rst <= '1'; wait_clk(5); rst <= '0'; wait_clk(2);

    -- Expected values for K=8, R=256 (Python-verified)
    run_test( 3,  5, 11,  5);
    run_test( 7,  9, 13,  7);
    run_test(10,  4, 17,  6);
    run_test(15,  6, 23,  7);

    wait_clk(5);
    report "TB_MONTGOMERY_MULT: pass=" & integer'image(pass_cnt)
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
