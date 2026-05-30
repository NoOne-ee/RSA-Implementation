-- =============================================================================
-- TB_RSA.vhd
-- Testbench for RSA wrapper (computes m^exp mod N).
--
-- Uses small toy keys so we can hand-verify with Python:
--    Key set 1:  N = 33  (= 3*11), e = 3, d = 7
--    Key set 2:  N = 143 (= 11*13), e = 7, d = 103
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RSA_PKG.all;

entity TB_RSA is
end entity;

architecture sim of TB_RSA is

  constant KEY_WIDTH  : positive := 2 * PRIME_WIDTH;
  constant CLK_PERIOD : time     := 10 ns;

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal start     : std_logic := '0';
  signal i_message : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal i_exp     : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal i_N       : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal o_done    : std_logic;
  signal o_result  : unsigned(KEY_WIDTH-1 downto 0);

  signal pass_cnt : integer := 0;
  signal fail_cnt : integer := 0;

begin

  clk <= not clk after CLK_PERIOD/2;

  DUT : entity work.RSA
    port map(
      clk       => clk,
      rst       => rst,
      start     => start,
      i_message => i_message,
      i_exp     => i_exp,
      i_N       => i_N,
      o_done    => o_done,
      o_result  => o_result
    );

  process

    procedure wait_clk(n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    procedure run_test(m, e, n_val, exp : integer) is
    begin
      i_message <= to_unsigned(m,     KEY_WIDTH);
      i_exp     <= to_unsigned(e,     KEY_WIDTH);
      i_N       <= to_unsigned(n_val, KEY_WIDTH);
      wait_clk(1);
      start <= '1'; wait_clk(1); start <= '0';

      while o_done /= '1' loop
        wait until rising_edge(clk);
      end loop;
      wait_clk(1);

      if to_integer(o_result) = exp then
        report "[PASS] " & integer'image(m) & "^" & integer'image(e)
             & " mod " & integer'image(n_val) & " = " & integer'image(exp)
          severity note;
        pass_cnt <= pass_cnt + 1;
      else
        report "[FAIL] " & integer'image(m) & "^" & integer'image(e)
             & " mod " & integer'image(n_val)
             & " expected=" & integer'image(exp)
             & " got=" & integer'image(to_integer(o_result))
          severity error;
        fail_cnt <= fail_cnt + 1;
      end if;
      wait_clk(3);
    end procedure;

  begin
    rst <= '1'; wait_clk(5); rst <= '0'; wait_clk(2);

    -- ===== Key 1: N=33, e=3, d=7 =====
    -- Encrypt:
    run_test( 2, 3, 33,  8);    -- 2^3 mod 33 = 8
    run_test( 4, 3, 33, 31);    -- 4^3 mod 33 = 64 mod 33 = 31
    run_test( 5, 3, 33, 26);    -- 5^3 mod 33 = 125 mod 33 = 26
    run_test( 7, 3, 33, 13);    -- 7^3 mod 33 = 343 mod 33 = 13
    run_test(17, 3, 33, 29);    -- 17^3 mod 33 = 4913 mod 33 = 29

    -- Decrypt (= encrypt of cipher with d):
    run_test( 8, 7, 33,  2);
    run_test(31, 7, 33,  4);
    run_test(26, 7, 33,  5);
    run_test(13, 7, 33,  7);
    run_test(29, 7, 33, 17);

    -- ===== Key 2: N=143, e=7, d=103 =====
    run_test(  2, 7, 143, 128);   -- 2^7 mod 143 = 128
    run_test( 17, 7, 143,  30);   -- 17^7 mod 143 = 30
    run_test( 42, 7, 143,  81);   -- 42^7 mod 143 = 81
    -- decrypt:
    run_test(128, 103, 143,  2);
    run_test( 30, 103, 143, 17);
    run_test( 81, 103, 143, 42);

    wait_clk(5);
    report "TB_RSA: pass=" & integer'image(pass_cnt)
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
