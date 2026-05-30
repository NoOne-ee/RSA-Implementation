-- =============================================================================
-- TB_RANDOM_GEN.vhd
-- Testbench for RANDOM_GEN (LFSR-based PRNG).
--
-- Checks that:
--   * After load + start the module raises o_done.
--   * Output has MSB=1 and LSB=1 (full-length odd number).
--   * Successive numbers are different (LFSR advances).
--   * Reloading the same seed reproduces the same sequence.
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TB_RANDOM_GEN is
end entity;

architecture sim of TB_RANDOM_GEN is

  constant WIDTH      : positive := 16;
  constant CLK_PERIOD : time     := 10 ns;

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal seed   : unsigned(127 downto 0) := (others => '0');
  signal load   : std_logic := '0';
  signal start  : std_logic := '0';
  signal o_done : std_logic;
  signal o_rng  : unsigned(WIDTH-1 downto 0);

  signal pass_cnt : integer := 0;
  signal fail_cnt : integer := 0;

begin

  clk <= not clk after CLK_PERIOD/2;

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

  process
    variable rng1, rng2, rng3 : unsigned(WIDTH-1 downto 0);

    procedure wait_clk(n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    procedure pulse_start is
    begin
      start <= '1'; wait_clk(1); start <= '0';
      while o_done /= '1' loop
        wait until rising_edge(clk);
      end loop;
      wait_clk(1);
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
      if cond then
        report "[PASS] " & msg severity note;
        pass_cnt <= pass_cnt + 1;
      else
        report "[FAIL] " & msg severity error;
        fail_cnt <= fail_cnt + 1;
      end if;
    end procedure;

  begin
    rst <= '1'; wait_clk(5); rst <= '0'; wait_clk(2);

    -- Load a known non-zero seed.
    seed <= x"DEADBEEFCAFEBABE0123456789ABCDEF";
    load <= '1'; wait_clk(2); load <= '0'; wait_clk(2);

    -- Generate three numbers
    pulse_start; rng1 := o_rng;
    pulse_start; rng2 := o_rng;
    pulse_start; rng3 := o_rng;

    report "rng1 = 0x" & integer'image(to_integer(rng1)) severity note;
    report "rng2 = 0x" & integer'image(to_integer(rng2)) severity note;
    report "rng3 = 0x" & integer'image(to_integer(rng3)) severity note;

    -- 1. MSB and LSB must both be 1.
    check(rng1(WIDTH-1) = '1', "rng1 MSB = 1 (full length)");
    check(rng1(0)       = '1', "rng1 LSB = 1 (odd)");
    check(rng2(WIDTH-1) = '1', "rng2 MSB = 1");
    check(rng2(0)       = '1', "rng2 LSB = 1");
    check(rng3(WIDTH-1) = '1', "rng3 MSB = 1");
    check(rng3(0)       = '1', "rng3 LSB = 1");

    -- 2. Successive numbers must differ (LFSR is advancing).
    check(rng1 /= rng2, "rng1 /= rng2 (LFSR advanced)");
    check(rng2 /= rng3, "rng2 /= rng3 (LFSR advanced)");

    -- 3. Reload same seed -> first number reproducible.
    seed <= x"DEADBEEFCAFEBABE0123456789ABCDEF";
    load <= '1'; wait_clk(2); load <= '0'; wait_clk(2);
    pulse_start;
    check(o_rng = rng1, "Reload same seed reproduces first number");

    wait_clk(5);
    report "TB_RANDOM_GEN: pass=" & integer'image(pass_cnt)
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
