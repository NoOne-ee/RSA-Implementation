-- =============================================================================
-- TB_EXT_GCD.vhd
-- Testbench for EXT_GCD (Extended Euclidean Algorithm / Modular Inverse)
--
-- Compile and run:
--   ghdl -i EXT_GCD.vhd TB_EXT_GCD.vhd
--   ghdl -m TB_EXT_GCD
--   ghdl -r TB_EXT_GCD --stop-time=10ms
--
-- Tests:
--   1. Simple known inverses (small numbers)
--   2. RSA-typical: e=65537 with small phi values
--   3. Cases where no inverse exists (gcd != 1)
--   4. Verification: (e * d) mod phi == 1
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TB_EXT_GCD is
end entity;

architecture SIM of TB_EXT_GCD is

  constant K : positive := 32;
  constant CLK_PERIOD : time := 10 ns;

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal start   : std_logic := '0';
  signal i_e     : unsigned(K-1 downto 0) := (others => '0');
  signal i_phi   : unsigned(K-1 downto 0) := (others => '0');
  signal o_done  : std_logic;
  signal o_valid : std_logic;
  signal o_d     : unsigned(K-1 downto 0);

  signal test_pass : integer := 0;
  signal test_fail : integer := 0;

begin

  -- Clock generation
  clk <= not clk after CLK_PERIOD / 2;

  -- DUT instantiation
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

    -- Test a modular inverse computation
    -- Verifies: (e * d) mod phi == 1
    procedure test_inverse(e_val : integer; phi_val : integer; name : string) is
      variable product : unsigned(2*K-1 downto 0);
      variable check   : unsigned(K-1 downto 0);
    begin
      i_e   <= to_unsigned(e_val, K);
      i_phi <= to_unsigned(phi_val, K);
      start <= '1';
      wait_clk(1);
      start <= '0';

      wait_done;
      wait_clk(1);

      if o_valid = '1' then
        -- Verify: (e * d) mod phi == 1
        product := to_unsigned(e_val, K) * o_d;
        check   := resize(product mod to_unsigned(phi_val, K), K);

        if check = to_unsigned(1, K) then
          report "[PASS] " & name & ": e=" & integer'image(e_val)
            & " phi=" & integer'image(phi_val)
            & " d=" & integer'image(to_integer(o_d))
            severity note;
          test_pass <= test_pass + 1;
        else
          report "[FAIL] " & name & ": e=" & integer'image(e_val)
            & " phi=" & integer'image(phi_val)
            & " d=" & integer'image(to_integer(o_d))
            & " but e*d mod phi /= 1"
            severity error;
          test_fail <= test_fail + 1;
        end if;
      else
        report "[FAIL] " & name & ": o_valid='0' but inverse should exist"
          severity error;
        test_fail <= test_fail + 1;
      end if;

      wait_clk(3);
    end procedure;

    -- Test cases where no inverse exists
    procedure test_no_inverse(e_val : integer; phi_val : integer; name : string) is
    begin
      i_e   <= to_unsigned(e_val, K);
      i_phi <= to_unsigned(phi_val, K);
      start <= '1';
      wait_clk(1);
      start <= '0';

      wait_done;
      wait_clk(1);

      if o_valid = '0' then
        report "[PASS] " & name & ": correctly reports no inverse"
          severity note;
        test_pass <= test_pass + 1;
      else
        report "[FAIL] " & name & ": should report no inverse but got d="
          & integer'image(to_integer(o_d))
          severity error;
        test_fail <= test_fail + 1;
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
    -- TEST GROUP 1: Simple known inverses
    -- ========================================================================
    report "=== TEST GROUP 1: Simple known inverses ===" severity note;

    -- 3^(-1) mod 7 = 5  (since 3*5 = 15 = 2*7 + 1)
    test_inverse(3, 7, "3^-1 mod 7");

    -- 7^(-1) mod 11 = 8  (since 7*8 = 56 = 5*11 + 1)
    test_inverse(7, 11, "7^-1 mod 11");

    -- 3^(-1) mod 11 = 4  (since 3*4 = 12 = 1*11 + 1)
    test_inverse(3, 11, "3^-1 mod 11");

    -- 17^(-1) mod 60 = 53  (since 17*53 = 901 = 15*60 + 1)
    test_inverse(17, 60, "17^-1 mod 60");

    -- ========================================================================
    -- TEST GROUP 2: RSA-typical values
    -- ========================================================================
    report "=== TEST GROUP 2: RSA-typical values ===" severity note;

    -- e=65537, phi = 3120 (from p=5, q=313 example... but let's use coprime)
    -- e=65537, phi = 120 (gcd(65537,120) = 1)
    -- 65537 mod 120 = 17, 17^-1 mod 120 = 113 (since 17*113 = 1921 = 16*120+1)
    test_inverse(65537, 120, "65537^-1 mod 120");

    -- e=65537, phi = 3016 (p=13, q=233 -> phi=12*232=2784... let me use simpler)
    -- e=17, phi = 3120  (RSA example: p=61, q=53 -> phi=60*52=3120)
    -- 17^-1 mod 3120 = 2753 (since 17*2753 = 46801 = 15*3120 + 1)
    test_inverse(17, 3120, "17^-1 mod 3120");

    -- e=65537, phi=5000 (random coprime test)
    test_inverse(65537, 5000, "65537^-1 mod 5000");

    -- ========================================================================
    -- TEST GROUP 3: No inverse exists (gcd != 1)
    -- ========================================================================
    report "=== TEST GROUP 3: No inverse (gcd != 1) ===" severity note;

    -- gcd(6, 9) = 3, no inverse
    test_no_inverse(6, 9, "6 mod 9 (gcd=3)");

    -- gcd(4, 8) = 4, no inverse
    test_no_inverse(4, 8, "4 mod 8 (gcd=4)");

    -- gcd(10, 15) = 5, no inverse
    test_no_inverse(10, 15, "10 mod 15 (gcd=5)");

    -- ========================================================================
    -- TEST GROUP 4: Larger values
    -- ========================================================================
    report "=== TEST GROUP 4: Larger values ===" severity note;

    -- e=65537, phi=65536 -> gcd=1 (65537 is prime, coprime with 65536)
    test_inverse(65537, 65536, "65537^-1 mod 65536");

    -- e=257, phi=65536 -> gcd=1 (257 is prime)
    test_inverse(257, 65536, "257^-1 mod 65536");

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
