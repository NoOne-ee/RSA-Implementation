library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RNS_PKG.all;
use work.RSA_PKG.all;

-- =============================================================================
-- RSA_TOP
--
-- The true top-level. Contains two sub-blocks wired together inside:
--
--     ┌──────────┐    N, e, d     ┌─────┐
--     │ KEYGEN_U │───────────────►│     │
--     └──────────┘                │ RSA │──► o_result
--                       i_message │     │
--     i_mode ── selects e or d ──►│     │
--                                 └─────┘
--
-- From the outside the user only drives:
--     i_message : the plaintext or ciphertext
--     i_mode    : '0' = encrypt, '1' = decrypt
--
-- Internally, on the first start after reset, KEYGEN_U runs once and the
-- derived (N, e, d) are latched. All subsequent operations reuse that key.
--
-- Key generics are forwarded to RSA_KEYGEN. Default: p=61, q=53, e=17 →
-- N=3233, d=2753 (the textbook RSA example; useful for simulation).
-- =============================================================================

entity RSA_TOP is
  generic(
    G_P : positive := 61;
    G_Q : positive := 53;
    G_E : positive := 17
  );
  port(
    clk        : in  std_logic;
    rst        : in  std_logic;
    start      : in  std_logic;

    i_message  : in  unsigned(INT_WIDTH-1 downto 0);
    i_mode     : in  std_logic;   -- '0' = encrypt (use e), '1' = decrypt (use d)

    o_done     : out std_logic;
    o_result   : out unsigned(INT_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RSA_TOP is

  -- ---- KEYGEN interface ----------------------------------------------------
  signal kg_start : std_logic := '0';
  signal kg_done  : std_logic;
  signal kg_N     : unsigned(INT_WIDTH-1 downto 0);
  signal kg_E     : unsigned(MOD_WIDTH-1 downto 0);
  signal kg_D     : unsigned(MOD_WIDTH-1 downto 0);

  -- Latched key (so we only run keygen once, first time through):
  signal N_reg : unsigned(INT_WIDTH-1 downto 0) := (others => '0');
  signal E_reg : unsigned(MOD_WIDTH-1 downto 0) := (others => '0');
  signal D_reg : unsigned(MOD_WIDTH-1 downto 0) := (others => '0');
  signal key_valid : std_logic := '0';

  -- ---- RSA core interface --------------------------------------------------
  signal rsa_start  : std_logic := '0';
  signal rsa_done   : std_logic;
  signal rsa_result : unsigned(INT_WIDTH-1 downto 0);
  signal exp_sel    : unsigned(MOD_WIDTH-1 downto 0);
  signal mode_reg   : std_logic := '0';

  -- ---- Top-level FSM -------------------------------------------------------
  -- IDLE         : waiting for user `start`.
  -- KEYGEN_START : pulse keygen start.
  -- KEYGEN_WAIT  : wait for keygen done, latch key.
  -- RSA_START    : pulse RSA start with selected exponent.
  -- RSA_WAIT     : wait for RSA done.
  -- OUTPUT       : present o_result + o_done for one cycle.
  type state_t is (IDLE, KEYGEN_START, KEYGEN_WAIT,
                   RSA_START, RSA_WAIT, OUTPUT);
  signal state : state_t := IDLE;

begin

  ---------------------------------------------------------------------------
  -- Sub-block 1: Key generator
  ---------------------------------------------------------------------------
  KEYGEN_U : entity work.RSA_KEYGEN
    generic map(
      G_P => G_P,
      G_Q => G_Q,
      G_E => G_E
    )
    port map(
      clk    => clk,
      rst    => rst,
      start  => kg_start,
      o_done => kg_done,
      o_N    => kg_N,
      o_E    => kg_E,
      o_D    => kg_D
    );

  ---------------------------------------------------------------------------
  -- Sub-block 2: RSA modular-exponentiation core
  ---------------------------------------------------------------------------
  RSA_CORE : entity work.RSA
    port map(
      clk       => clk,
      rst       => rst,
      start     => rsa_start,
      i_message => i_message,
      i_exp     => exp_sel,
      i_N       => N_reg,
      o_done    => rsa_done,
      o_result  => rsa_result
    );

  -- Select exponent: encrypt → e, decrypt → d.
  exp_sel <= D_reg when mode_reg = '1' else E_reg;

  ---------------------------------------------------------------------------
  -- Top-level control FSM
  ---------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state     <= IDLE;
        kg_start  <= '0';
        rsa_start <= '0';
        o_done    <= '0';
        o_result  <= (others => '0');
        N_reg     <= (others => '0');
        E_reg     <= (others => '0');
        D_reg     <= (others => '0');
        key_valid <= '0';
        mode_reg  <= '0';
      else
        -- default pulse-low signals
        kg_start  <= '0';
        rsa_start <= '0';
        o_done    <= '0';

        case state is

          when IDLE =>
            if start = '1' then
              mode_reg <= i_mode;
              if key_valid = '0' then
                kg_start <= '1';
                state    <= KEYGEN_START;
              else
                state <= RSA_START;
              end if;
            end if;

          when KEYGEN_START =>
            -- kg_start was asserted last cycle; just wait for kg_done.
            state <= KEYGEN_WAIT;

          when KEYGEN_WAIT =>
            if kg_done = '1' then
              N_reg     <= kg_N;
              E_reg     <= kg_E;
              D_reg     <= kg_D;
              key_valid <= '1';
              state     <= RSA_START;
            end if;

          when RSA_START =>
            -- One cycle to let exp_sel settle (driven by mode_reg + E_reg/D_reg
            -- registered last cycle), then pulse start.
            rsa_start <= '1';
            state     <= RSA_WAIT;

          when RSA_WAIT =>
            if rsa_done = '1' then
              state <= OUTPUT;
            end if;

          when OUTPUT =>
            o_result <= rsa_result;
            o_done   <= '1';
            state    <= IDLE;

        end case;
      end if;
    end if;
  end process;

end RTL;
