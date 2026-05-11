-- =============================================================================
-- TB_RSA_TOP.vhd
--
-- Testbench for the unified RSA_TOP (keygen + encrypt + decrypt in one block).
-- The user only feeds messages; RSA_TOP handles N, e, d internally.
--
-- Flow:
--   1. Reset, load a non-zero seed.
--   2. Pulse gen_keys, wait for keys_ready.
--   3. Encrypt a message, remember the ciphertext.
--   4. Decrypt the ciphertext, check that we got the original message back.
--   5. Repeat for a few more messages.
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TB_RSA_TOP is
end entity;

architecture SIM of TB_RSA_TOP is

  constant PRIME_WIDTH : positive := 16;
  constant KEY_WIDTH   : positive := 2 * PRIME_WIDTH;
  constant CLK_PERIOD  : time     := 10 ns;

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';

  -- Keygen
  signal seed       : unsigned(127 downto 0) := (others => '0');
  signal load       : std_logic := '0';
  signal gen_keys   : std_logic := '0';
  signal keys_ready : std_logic;

  -- Encrypt / decrypt
  signal i_message  : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal mode       : std_logic := '0';
  signal start      : std_logic := '0';
  signal o_done     : std_logic;
  signal o_result   : unsigned(KEY_WIDTH-1 downto 0);

  -- Keys (debug)
  signal o_N        : unsigned(KEY_WIDTH-1 downto 0);
  signal o_e        : unsigned(KEY_WIDTH-1 downto 0);
  signal o_d        : unsigned(KEY_WIDTH-1 downto 0);

  signal test_pass  : integer := 0;
  signal test_fail  : integer := 0;

begin

  clk <= not clk after CLK_PERIOD / 2;

  DUT : entity work.RSA_TOP
    generic map(
      PRIME_WIDTH   => PRIME_WIDTH,
      NUM_WITNESSES => 4
    )
    port map(
      clk        => clk,
      rst        => rst,
      seed       => seed,
      load       => load,
      gen_keys   => gen_keys,
      keys_ready => keys_ready,
      i_message  => i_message,
      mode       => mode,
      start      => start,
      o_done     => o_done,
      o_result   => o_result,
      o_N        => o_N,
      o_e        => o_e,
      o_d        => o_d
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
      while keys_ready /= '1' loop
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

    -- One round-trip: encrypt M, then decrypt, verify equality.
    procedure round_trip(m : in unsigned(KEY_WIDTH-1 downto 0); label : in string) is
      variable cipher : unsigned(KEY_WIDTH-1 downto 0);
    begin
      -- Encrypt
      i_message <= m;
      mode      <= '0';
      start     <= '1';
      wait_clk(1);
      start     <= '0';
      wait_done;
      wait_clk(1);
      cipher := o_result;
      check(cipher /= m, label & ": ciphertext differs from plaintext");

      -- Decrypt
      i_message <= cipher;
      mode      <= '1';
      start     <= '1';
      wait_clk(1);
      start     <= '0';
      wait_done;
      wait_clk(1);
      check(o_result = m, label & ": decrypt(encrypt(M)) = M");
    end procedure;

  begin
    -- Reset
    rst <= '1';
    wait_clk(5);
    rst <= '0';
    wait_clk(3);

    report "============================================" severity note;
    report "  PHASE 1: Generating RSA key pair" severity note;
    report "============================================" severity note;

    seed <= x"DEADBEEFCAFEBABE1234567890ABCDEF";
    load <= '1';
    wait_clk(1);
    load <= '0';
    wait_clk(2);

    gen_keys <= '1';
    wait_clk(1);
    gen_keys <= '0';

    wait_keys;
    wait_clk(2);
    check(keys_ready = '1', "Keys generated successfully");

    wait_clk(5);

    report "============================================" severity note;
    report "  PHASE 2: Round-trip M=42" severity note;
    report "============================================" severity note;
    round_trip(to_unsigned(42, KEY_WIDTH), "M=42");

    wait_clk(5);
    report "============================================" severity note;
    report "  PHASE 3: Round-trip M=99" severity note;
    report "============================================" severity note;
    round_trip(to_unsigned(99, KEY_WIDTH), "M=99");

    wait_clk(5);
    report "============================================" severity note;
    report "  PHASE 4: Round-trip M=12345" severity note;
    report "============================================" severity note;
    round_trip(to_unsigned(12345, KEY_WIDTH), "M=12345");

    wait_clk(10);
    report "============================================" severity note;
    report "  RESULTS:  passed=" & integer'image(test_pass) &
           "  failed=" & integer'image(test_fail) severity note;
    report "============================================" severity note;

    if test_fail = 0 then
      report "  ALL TESTS PASSED" severity note;
    else
      report "  SOME TESTS FAILED" severity error;
    end if;

    wait for 100 ns;
    assert false report "Simulation finished" severity failure;
  end process;

end SIM;
