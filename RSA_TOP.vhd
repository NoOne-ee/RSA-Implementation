library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RSA_PKG.all;

-- =============================================================================
-- RSA_TOP
--
-- Top-level RSA entity with built-in key generation.
-- The user only needs to provide:
--     i_message : the plaintext (for encryption) or ciphertext (for decryption)
--     i_mode    : '0' = encrypt (uses public exponent e)
--                 '1' = decrypt (uses private exponent d)
--
-- Key parameters (p, q, e) are generics. N = p*q, phi = (p-1)*(q-1), and
-- d = e^-1 mod phi are computed at elaboration time — no runtime big-int math.
--
-- Default key (textbook example):
--     p = 61, q = 53  →  N = 3233, e = 17, d = 2753
--
-- For your own keys: override the generics with your chosen primes and e.
-- Constraint: p*q and (p-1)*(q-1) must fit in a VHDL integer (2^31 - 1) for
-- the elaboration-time computation. For larger keys, pre-compute N, e, d
-- externally and use the RSA entity directly.
-- =============================================================================

entity RSA_TOP is
  generic(
    G_P : positive := 61;    -- first prime
    G_Q : positive := 53;    -- second prime
    G_E : positive := 17     -- public exponent (must be coprime to phi)
  );
  port(
    clk        : in  std_logic;
    rst        : in  std_logic;
    start      : in  std_logic;

    i_message  : in  unsigned(INT_WIDTH-1 downto 0);
    i_mode     : in  std_logic;  -- '0' = encrypt, '1' = decrypt

    o_done     : out std_logic;
    o_result   : out unsigned(INT_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RSA_TOP is

  -- Key derivation at elaboration time:
  constant C_N   : positive := G_P * G_Q;
  constant C_PHI : positive := (G_P - 1) * (G_Q - 1);
  constant C_D   : positive := mod_inverse_fn(G_E, C_PHI);

  -- Widen to the datapath sizes:
  constant C_N_VEC : unsigned(INT_WIDTH-1 downto 0) := to_unsigned(C_N, INT_WIDTH);
  constant C_E_VEC : unsigned(MOD_WIDTH-1 downto 0) := to_unsigned(G_E, MOD_WIDTH);
  constant C_D_VEC : unsigned(MOD_WIDTH-1 downto 0) := to_unsigned(C_D, MOD_WIDTH);

  -- Internal signals to mux the exponent:
  signal exp_sel : unsigned(MOD_WIDTH-1 downto 0);

  -- RSA core interface:
  signal rsa_start  : std_logic;
  signal rsa_done   : std_logic;
  signal rsa_result : unsigned(INT_WIDTH-1 downto 0);

  -- FSM to latch mode at start time and drive the RSA core:
  type state_t is (IDLE, RUN, WAIT_DONE, OUTPUT);
  signal state : state_t := IDLE;

  signal mode_reg : std_logic := '0';

begin

  -- Select exponent based on latched mode:
  exp_sel <= C_D_VEC when mode_reg = '1' else C_E_VEC;

  -- Instantiate the existing RSA modular-exponentiation core:
  RSA_CORE : entity work.RSA
    port map(
      clk       => clk,
      rst       => rst,
      start     => rsa_start,
      i_message => i_message,
      i_exp     => exp_sel,
      i_N       => C_N_VEC,
      o_done    => rsa_done,
      o_result  => rsa_result
    );

  -- Simple FSM: latch mode, kick off RSA core, wait, output.
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state     <= IDLE;
        rsa_start <= '0';
        o_done    <= '0';
        o_result  <= (others => '0');
        mode_reg  <= '0';
      else
        rsa_start <= '0';
        o_done    <= '0';

        case state is
          when IDLE =>
            if start = '1' then
              mode_reg <= i_mode;
              state    <= RUN;
            end if;

          when RUN =>
            -- One cycle to let exp_sel settle with the latched mode_reg,
            -- then pulse start to the RSA core.
            rsa_start <= '1';
            state     <= WAIT_DONE;

          when WAIT_DONE =>
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
