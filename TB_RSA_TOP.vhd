-- =============================================================================
-- TB_RSA_TOP.vhd
--
-- Testbench for the simplified RSA_TOP.
-- The only user-facing inputs are clk, rst, i_message, mode, start.
-- After reset, RSA_TOP auto-seeds its PRNG and runs keygen. We detect
-- completion by watching o_N go non-zero.
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RSA_PKG.all;

entity TB_RSA_TOP is
end entity;

architecture SIM of TB_RSA_TOP is

  constant KEY_WIDTH  : positive := 2 * PRIME_WIDTH;
  constant CLK_PERIOD : time     := 10 ns;

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';

  signal i_message : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal mode      : std_logic := '0';
  signal start     : std_logic := '0';
  signal o_done    : std_logic;
  signal o_result  : unsigned(KEY_WIDTH-1 downto 0);

  signal o_N       : unsigned(KEY_WIDTH-1 downto 0);
  signal o_e       : unsigned(KEY_WIDTH-1 downto 0);
  signal o_d       : unsigned(KEY_WIDTH-1 downto 0);

  signal test_pass : integer := 0;
  signal test_fail : integer := 0;

begin

  clk <= not clk after CLK_PERIOD / 2;

  DUT : entity work.RSA_TOP
    port map(
      clk       => clk,
      rst       => rst,
      i_message => i_message,
      mode      => mode,
      start     => start,
      o_done    => o_done,
      o_result  => o_result,
      o_N       => o_N,
      o_e       => o_e,
      o_d       => o_d
    );

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
        if timeout > 50000000 then
          report "[TIMEOUT] Operation stuck!" severity error;
          exit;
        end if;
      end loop;
    end procedure;

    procedure wait_keys is
      variable timeout : integer := 0;
    begin
      while o_N = 0 loop
        wait until rising_edge(clk);
        timeout := timeout + 1;
        if timeout > 50000000 then
          report "[TIMEOUT] Key generation stuck!" severity error;
          exit;
        end if;
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

    procedure round_trip(m : in unsigned(KEY_WIDTH-1 downto 0); tag : in string) is
      variable cipher : unsigned(KEY_WIDTH-1 downto 0);
    begin
      i_message <= m;
      mode      <= '0';
      start     <= '1';
      wait_clk(1);
      start     <= '0';
      wait_done;
      wait_clk(1);
      cipher := o_result;
      check(cipher /= m, tag & ": ciphertext differs from plaintext");

      i_message <= cipher;
      mode      <= '1';
      start     <= '1';
      wait_clk(1);
      start     <= '0';
      wait_done;
      wait_clk(1);
      check(o_result = m, tag & ": decrypt(encrypt(M)) = M");
    end procedure;

  begin
    rst <= '1';
    wait_clk(5);
    rst <= '0';

    wait_keys;
    wait_clk(2);
    check(o_N /= 0, "Keys generated automatically after reset");

    wait_clk(5);
    round_trip(to_unsigned(42, KEY_WIDTH), "M=42");

    wait_clk(5);
    round_trip(to_unsigned(99, KEY_WIDTH), "M=99");

    wait_clk(5);
    round_trip(to_unsigned(12345, KEY_WIDTH), "M=12345");

    wait_clk(10);
    report "RESULTS: passed=" & integer'image(test_pass) &
           " failed=" & integer'image(test_fail) severity note;

    if test_fail = 0 then
      report "ALL TESTS PASSED" severity note;
    else
      report "SOME TESTS FAILED" severity error;
    end if;

    wait for 100 ns;
    assert false report "Simulation finished" severity failure;
  end process;

end SIM;
