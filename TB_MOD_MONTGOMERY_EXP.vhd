-- =============================================================================
-- TB_MOD_MONTGOMERY_EXP.vhd
-- Testbench for MOD_MONTGOMERY_EXP.
-- Computes Z = X^E mod M.
-- Expected values precomputed with Python pow().
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TB_MOD_MONTGOMERY_EXP is
end entity;

architecture sim of TB_MOD_MONTGOMERY_EXP is

  constant K          : positive := 8;
  constant CLK_PERIOD : time     := 10 ns;

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal start  : std_logic := '0';
  signal i_X    : unsigned(K-1 downto 0) := (others => '0');
  signal i_E    : unsigned(K-1 downto 0) := (others => '0');
  signal i_Mod  : unsigned(K-1 downto 0) := (others => '0');
  signal o_done : std_logic;
  signal o_Z    : unsigned(K-1 downto 0);

  signal pass_cnt : integer := 0;
  signal fail_cnt : integer := 0;

begin

  clk <= not clk after CLK_PERIOD/2;

  DUT : entity work.MOD_MONTGOMERY_EXP
    generic map(K => K)
    port map(
      clk    => clk,
      rst    => rst,
      start  => start,
      i_X    => i_X,
      i_e    => i_E,
      i_Mod  => i_Mod,
      o_done => o_done,
      o_Z    => o_Z
    );

  process
    procedure wait_clk(n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    procedure run_test(x, e, m, exp : integer) is
    begin
      i_X   <= to_unsigned(x, K);
      i_E   <= to_unsigned(e, K);
      i_Mod <= to_unsigned(m, K);
      wait_clk(1);
      start <= '1'; wait_clk(1); start <= '0';

      while o_done /= '1' loop
        wait until rising_edge(clk);
      end loop;
      wait_clk(1);

      if to_integer(o_Z) = exp then
        report "[PASS] " & integer'image(x) & "^" & integer'image(e)
             & " mod " & integer'image(m) & " = " & integer'image(exp)
          severity note;
        pass_cnt <= pass_cnt + 1;
      else
        report "[FAIL] " & integer'image(x) & "^" & integer'image(e)
             & " mod " & integer'image(m)
             & " expected=" & integer'image(exp)
             & " got=" & integer'image(to_integer(o_Z))
          severity error;
        fail_cnt <= fail_cnt + 1;
      end if;
      wait_clk(3);
    end procedure;

  begin
    rst <= '1'; wait_clk(5); rst <= '0'; wait_clk(2);

    -- Python-verified expected values
    run_test(3,  7, 11,  9);   -- 3^7 mod 11 = 9
    run_test(5,  3, 13,  8);   -- 5^3 mod 13 = 8
    run_test(2, 10, 17,  4);   -- 2^10 mod 17 = 4
    run_test(4,  5, 19, 17);   -- 4^5 mod 19 = 17

    wait_clk(5);
    report "TB_MOD_MONTGOMERY_EXP: pass=" & integer'image(pass_cnt)
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
