library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RNS_PKG.all;
use work.RSA_PKG.all;

-- =============================================================================
-- RSA_KEYGEN
--
-- Produces the RSA key material (N, e, d) derived from the two primes (p, q)
-- and public exponent e passed in as generics.
--
-- Why generics instead of runtime prime generation?
--     A real on-chip keygen (random prime search + primality testing + EEA
--     on 1024-bit numbers) is a very large separate design. For this RTL it
--     is far cleaner and perfectly correct to bake the key in at elaboration
--     time: the user of RSA_TOP still only drives a message, and the key is
--     computed without any software step on the side. If you ever want
--     runtime keygen, this entity is the drop-in replacement point.
--
-- Behavior:
--     After `start` is asserted, the module pulses `o_done` for one cycle
--     and presents N, e, d on its output ports. They remain stable until
--     the next reset or the next `start`. This gives RSA_TOP a proper
--     request/acknowledge handshake rather than having the key appear out
--     of nowhere.
-- =============================================================================

entity RSA_KEYGEN is
  generic(
    G_P : positive := 61;   -- first prime
    G_Q : positive := 53;   -- second prime
    G_E : positive := 17    -- public exponent (must be coprime to (p-1)(q-1))
  );
  port(
    clk     : in  std_logic;
    rst     : in  std_logic;
    start   : in  std_logic;

    o_done  : out std_logic;
    o_N     : out unsigned(INT_WIDTH-1 downto 0);
    o_E     : out unsigned(MOD_WIDTH-1 downto 0);
    o_D     : out unsigned(MOD_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RSA_KEYGEN is

  -- Elaboration-time key derivation:
  constant C_N   : positive := G_P * G_Q;
  constant C_PHI : positive := (G_P - 1) * (G_Q - 1);
  constant C_D   : positive := mod_inverse_fn(G_E, C_PHI);

  -- Vectorised key material:
  constant C_N_VEC : unsigned(INT_WIDTH-1 downto 0) := to_unsigned(C_N, INT_WIDTH);
  constant C_E_VEC : unsigned(MOD_WIDTH-1 downto 0) := to_unsigned(G_E, MOD_WIDTH);
  constant C_D_VEC : unsigned(MOD_WIDTH-1 downto 0) := to_unsigned(C_D, MOD_WIDTH);

  -- Trivial two-state handshake: IDLE -> RESPOND -> IDLE
  type state_t is (IDLE, RESPOND);
  signal state : state_t := IDLE;

begin

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state  <= IDLE;
        o_done <= '0';
        o_N    <= (others => '0');
        o_E    <= (others => '0');
        o_D    <= (others => '0');
      else
        o_done <= '0';

        case state is

          when IDLE =>
            if start = '1' then
              -- Present the key and acknowledge next cycle.
              o_N   <= C_N_VEC;
              o_E   <= C_E_VEC;
              o_D   <= C_D_VEC;
              state <= RESPOND;
            end if;

          when RESPOND =>
            o_done <= '1';
            state  <= IDLE;

        end case;
      end if;
    end if;
  end process;

end RTL;
