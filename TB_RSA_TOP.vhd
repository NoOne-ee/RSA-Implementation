library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RSA_PKG.all;

-- =============================================================================
-- TB_RSA_TOP
--
-- Testbench for RSA_TOP. Uses the default key (p=61, q=53, e=17 → N=3233, d=2753).
--
-- Tests:
--   1. Encrypt a message, verify ciphertext matches Python: pow(msg, 17, 3233)
--   2. Decrypt the ciphertext, verify we get back the original message.
--   3. Round-trip: encrypt then decrypt several messages.
-- =============================================================================

entity TB_RSA_TOP is
end entity;

architecture sim of TB_RSA_TOP is

  constant CLK_PERIOD : time := 10 ns;

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal start     : std_logic := '0';
  signal i_message : unsigned(INT_WIDTH-1 downto 0) := (others => '0');
  signal i_mode    : std_logic := '0';
  signal o_done    : std_logic;
  signal o_result  : unsigned(INT_WIDTH-1 downto 0);

begin

  DUT : entity work.RSA_TOP
    generic map(
      G_P => 61,
      G_Q => 53,
      G_E => 17
    )
    port map(
      clk       => clk,
      rst       => rst,
      start     => start,
      i_message => i_message,
      i_mode    => i_mode,
      o_done    => o_done,
      o_result  => o_result
    );

  clk <= not clk after CLK_PERIOD / 2;

  process

    -- Helper: run one encrypt or decrypt operation.
    procedure run_op(
      constant msg      : in integer;
      constant mode     : in std_logic;   -- '0'=encrypt, '1'=decrypt
      constant expected : in integer
    ) is
      variable mode_str : string(1 to 7);
    begin
      if mode = '0' then mode_str := "ENCRYPT"; else mode_str := "DECRYPT"; end if;

      i_message <= to_unsigned(msg, INT_WIDTH);
      i_mode    <= mode;

      wait until rising_edge(clk);
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';

      wait until o_done = '1';
      wait until falling_edge(clk);

      if to_integer(o_result) = expected then
        report "PASS [" & mode_str & "]: " & integer'image(msg)
               & " -> " & integer'image(to_integer(o_result));
      else
        report "FAIL [" & mode_str & "]: " & integer'image(msg)
               & "  expected=" & integer'image(expected)
               & "  got=" & integer'image(to_integer(o_result))
          severity error;
      end if;

      wait for 3 * CLK_PERIOD;
    end procedure;

  begin
    -- Reset
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    rst <= '0';
    wait until rising_edge(clk);

    -- =========================================================================
    -- Test 1: Encrypt  (pow(65, 17, 3233) = 2790)
    -- =========================================================================
    run_op(65, '0', 2790);

    -- =========================================================================
    -- Test 2: Decrypt  (pow(2790, 2753, 3233) = 65)
    -- =========================================================================
    run_op(2790, '1', 65);

    -- =========================================================================
    -- Test 3: Round-trip several messages
    --   msg=123  → encrypt → pow(123,17,3233)=855   → decrypt → 123
    --   msg=42   → encrypt → pow(42,17,3233)=2557   → decrypt → 42
    --   msg=1000 → encrypt → pow(1000,17,3233)=175  → decrypt → 1000
    -- =========================================================================
    run_op(123,  '0', 855);
    run_op(855,  '1', 123);

    run_op(42,   '0', 2557);
    run_op(2557, '1', 42);

    run_op(1000, '0', 175);
    run_op(175,  '1', 1000);

    report "=== ALL TB_RSA_TOP TESTS FINISHED ===";
    wait;
  end process;

end architecture;
