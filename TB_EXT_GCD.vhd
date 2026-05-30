-- =============================================================================
-- TB_EXT_GCD.vhd
-- Testbench for EXT_GCD (modular inverse via Extended Euclidean Algorithm).
--
-- Computes d = e^(-1) mod phi.
-- Expected values precomputed with Python pow(e, -1, phi).
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TB_EXT_GCD is
end entity;

architecture sim of TB_EXT_GCD is

  constant K          : positive := 16;
  constant CLK_PERIOD : time     := 10 ns;

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal start   : std_logic := '0';
  signal i_e     : unsigned(K-1 downto 0) := (others => '0');
  signal i_phi   : unsigned(K-1 downto 0) := (others => '0');
  signal o_done  : std_logic;
  signal o_valid : std_logic;
  signal o_d     : unsigned(K-1 downto 0);

  signal pass_cnt : integer := 0;
  signal fail_cnt : integer := 0;

begin

  clk <= not clk after CLK_PERIOD/2;

  DUT : entity work.EXT_GCD
    generic map(K => K)
    port map(
      clk     => clk,
      rst     => rst,
      start   => start,
      i_e     => i_e,
      i_phi   => i_phi,
      o_done  => o_done,
      o_valid => o_valid,
      o_d     => o_d
    );

  process

    procedure wait_clk(n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    procedure run_test(e, phi, exp_d : integer; exp_valid : std_logic) is
      variable label : string(1 to 8);
    begin
      i_e   <= to_unsigned(e,   K);
      i_phi <= to_unsigned(phi, K);
      wait_clk(1);
      start <= '1'; wait_clk(1); start <= '0';

      while o_done /= '1' loop
        wait until rising_edge(clk);
      end loop;
      wait_clk(1);

      if exp_valid = '1' then
        if o_valid = '1' and to_integer(o_d) = exp_d then
          report "[PASS] inverse(" & integer'image(e) & "," & integer'image(phi)
               & ") = " & integer'image(exp_d) severity note;
          pass_cnt <= pass_cnt + 1;
        else
          report "[FAIL] inverse(" & integer'image(e) & "," & integer'image(phi)
               & ") expected=" & integer'image(exp_d)
               & " got_valid=" & std_logic'image(o_valid)
               & " got_d=" & integer'image(to_integer(o_d))
            severity error;
          fail_cnt <= fail_cnt + 1;
        end if;
      else
        if o_valid = '0' then
          report "[PASS] inverse(" & integer'image(e) & "," & integer'image(phi)
               & ") correctly reported NO INVERSE" severity note;
          pass_cnt <= pass_cnt + 1;
        else
          report "[FAIL] inverse(" & integer'image(e) & "," & integer'image(phi)
               & ") should be invalid but got " & integer'image(to_integer(o_d))
            severity error;
          fail_cnt <= fail_cnt + 1;
        end if;
      end if;
      wait_clk(2);
    end procedure;

  begin
    rst <= '1'; wait_clk(5); rst <= '0'; wait_clk(2);

    -- Python-verified expected values
    run_test( 3, 11,  4, '1');   -- 3^-1 mod 11 = 4
    run_test( 7, 15, 13, '1');   -- 7^-1 mod 15 = 13
    run_test( 7, 40, 23, '1');   -- 7^-1 mod 40 = 23
    run_test( 3, 40, 27, '1');   -- 3^-1 mod 40 = 27
    run_test(11, 30, 11, '1');   -- 11^-1 mod 30 = 11
    run_test( 5, 21, 17, '1');   -- 5^-1 mod 21 = 17

    -- Case where gcd(e, phi) /= 1, no inverse:
    run_test( 6, 9,   0, '0');   -- gcd(6,9)=3, no inverse

    wait_clk(5);
    report "TB_EXT_GCD: pass=" & integer'image(pass_cnt)
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
