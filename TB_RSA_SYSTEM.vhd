-- =============================================================================
-- TB_RSA_SYSTEM.vhd
-- Testbench for the complete RSA System (keygen + encrypt + decrypt)
--
-- Demonstrates the full RSA flow:
--   1. Generate keys (N, e, d)
--   2. Encrypt a message: C = M^e mod N
--   3. Decrypt the ciphertext: M' = C^d mod N
--   4. Verify M' == M (round-trip)
--
-- Compile and run:
--   ghdl -i MONTGOMERY_MULT.vhd MOD_MONTGOMERY_EXP.vhd RANDOM_GEN.vhd
--        MILLER_RABIN.vhd EXT_GCD.vhd RSA_KEYGEN.vhd RSA_SYSTEM.vhd
--        TB_RSA_SYSTEM.vhd
--   ghdl -m TB_RSA_SYSTEM
--   ghdl -r TB_RSA_SYSTEM --stop-time=2000ms
--
-- Uses PRIME_WIDTH=16 (32-bit keys) for fast simulation.
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TB_RSA_SYSTEM is
end entity;

architecture SIM of TB_RSA_SYSTEM is

  constant PRIME_WIDTH : positive := 16;
  constant KEY_WIDTH   : positive := 2 * PRIME_WIDTH;
  constant CLK_PERIOD  : time := 10 ns;

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';

  -- Key generation
  signal seed       : unsigned(127 downto 0) := (others => '0');
  signal load       : std_logic := '0';
  signal gen_keys   : std_logic := '0';
  signal keys_ready : std_logic;

  -- Encrypt/Decrypt
  signal i_message  : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal mode       : std_logic := '0';
  signal start      : std_logic := '0';
  signal o_done     : std_logic;
  signal o_result   : unsigned(KEY_WIDTH-1 downto 0);

  -- Key outputs
  signal o_N        : unsigned(KEY_WIDTH-1 downto 0);
  signal o_e        : unsigned(KEY_WIDTH-1 downto 0);
  signal o_d        : unsigned(KEY_WIDTH-1 downto 0);

  -- Test storage
  signal ciphertext : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal plaintext  : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');

  signal test_pass  : integer := 0;
  signal test_fail  : integer := 0;

begin

  -- Clock generation
  clk <= not clk after CLK_PERIOD / 2;

  -- DUT instantiation
  DUT : entity work.RSA_SYSTEM
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

  -- Stimulus
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

    constant MSG1 : unsigned(KEY_WIDTH-1 downto 0) := to_unsigned(42, KEY_WIDTH);
    constant MSG2 : unsigned(KEY_WIDTH-1 downto 0) := to_unsigned(12345, KEY_WIDTH);
    constant MSG3 : unsigned(KEY_WIDTH-1 downto 0) := to_unsigned(99, KEY_WIDTH);

  begin
    -- ========================================================================
    -- Reset
    -- ========================================================================
    rst <= '1';
    wait_clk(5);
    rst <= '0';
    wait_clk(3);

    -- ========================================================================
    -- PHASE 1: Key Generation
    -- ========================================================================
    report "============================================" severity note;
    report "  PHASE 1: Generating RSA Key Pair" severity note;
    report "============================================" severity note;

    -- Load seed
    seed <= x"DEADBEEFCAFEBABE1234567890ABCDEF";
    load <= '1';
    wait_clk(1);
    load <= '0';
    wait_clk(2);

    -- Start key generation
    gen_keys <= '1';
    wait_clk(1);
    gen_keys <= '0';

    -- Wait for keys
    wait_keys;
    wait_clk(2);

    check(keys_ready = '1', "Keys generated successfully");
    report "  Keys are ready!" severity note;

    wait_clk(5);

    -- ========================================================================
    -- PHASE 2: Encrypt message
    -- ========================================================================
    report "============================================" severity note;
    report "  PHASE 2: Encrypting message M=42" severity note;
    report "============================================" severity note;

    i_message <= MSG1;
    mode      <= '0';  -- encrypt
    start     <= '1';
    wait_clk(1);
    start     <= '0';

    wait_done;
    wait_clk(1);

    ciphertext <= o_result;
    check(o_result /= MSG1, "Ciphertext differs from plaintext");
    report "  Encryption complete" severity note;

    wait_clk(5);

    -- ========================================================================
    -- PHASE 3: Decrypt ciphertext
    -- ========================================================================
    report "============================================" severity note;
    report "  PHASE 3: Decrypting ciphertext" severity note;
    report "============================================" severity note;

    i_message <= ciphertext;
    mode      <= '1';  -- decrypt
    start     <= '1';
    wait_clk(1);
    start     <= '0';

    wait_done;
    wait_clk(1);

    plaintext <= o_result;

    -- ========================================================================
    -- PHASE 4: Verify round-trip
    -- ========================================================================
    report "============================================" severity note;
    report "  PHASE 4: Verifying M' == M (round-trip)" severity note;
    report "============================================" severity note;

    check(o_result = MSG1, "ROUND-TRIP: Decrypted == Original (M=42)");

    if o_result = MSG1 then
      report "  SUCCESS: decrypt(encrypt(42)) = 42" severity note;
    else
      report "  MISMATCH: expected 42, got " & integer'image(to_integer(o_result)) severity error;
    end if;

    wait_clk(5);

    -- ========================================================================
    -- PHASE 5: Test with another message
    -- ========================================================================
    report "============================================" severity note;
    report "  PHASE 5: Testing with M=99" severity note;
    report "============================================" severity note;

    -- Encrypt
    i_message <= MSG3;
    mode      <= '0';
    start     <= '1';
    wait_clk(1);
    start     <= '0';
    wait_done;
    wait_clk(1);

    ciphertext <= o_result;
    check(o_result /= MSG3, "Ciphertext for M=99 differs from plaintext");

    -- Decrypt
    i_message <= o_result;
    mode      <= '1';
    start     <= '1';
    wait_clk(1);
    start     <= '0';
    wait_done;
    wait_clk(1);

    check(o_result = MSG3, "ROUND-TRIP: Decrypted == Original (M=99)");

    if o_result = MSG3 then
      report "  SUCCESS: decrypt(encrypt(99)) = 99" severity note;
    else
      report "  MISMATCH: expected 99, got " & integer'image(to_integer(o_result)) severity error;
    end if;

    wait_clk(5);

    -- ========================================================================
    -- Summary
    -- ========================================================================
    report "============================================" severity note;
    report "  FINAL RESULTS" severity note;
    report "============================================" severity note;
    report "  TESTS PASSED: " & integer'image(test_pass) severity note;
    report "  TESTS FAILED: " & integer'image(test_fail) severity note;
    report "============================================" severity note;

    if test_fail = 0 then
      report "  ALL TESTS PASSED - RSA SYSTEM WORKS!" severity note;
    else
      report "  SOME TESTS FAILED!" severity error;
    end if;

    wait for 100 ns;
    assert false report "Simulation finished" severity failure;
  end process;

end SIM;
