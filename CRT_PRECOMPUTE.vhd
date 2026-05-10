library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RNS_PKG.all;

entity CRT_PRECOMPUTE is
  port(
    clk      : in  std_logic;
    rst      : in  std_logic;
    start    : in  std_logic;

    i_moduli : in  mod_array_t(0 to NUM_MODULI-1);

    o_done   : out std_logic;
    o_M      : out unsigned(INT_WIDTH-1 downto 0);
    o_K      : out crt_array_t(0 to NUM_MODULI-1)
  );
end entity;

architecture RTL of CRT_PRECOMPUTE is

  function mod_inverse(a : integer; m : integer) return integer is
    variable t     : integer := 0;
    variable new_t : integer := 1;
    variable r     : integer := m;
    variable new_r : integer := a;
    variable q     : integer;
    variable temp  : integer;
  begin
  
    for i in 0 to 2*MOD_WIDTH loop
	    if new_r /= 0 then 
		    q := r / new_r;

            temp  := t - q * new_t;
            t     := new_t;
            new_t := temp;

            temp  := r - q * new_r;
            r     := new_r;
            new_r := temp;
		end if;
	end loop;

    if t < 0 then
      t := t + m;
    end if;

    return t;
  end function;

begin

  process(clk)
    variable M_total : unsigned(2*INT_WIDTH-1 downto 0);
    variable Mi      : unsigned(2*INT_WIDTH-1 downto 0);
    variable m_i     : integer;
    variable inv_i   : integer;
    variable Ki      : integer;
  begin
    if rising_edge(clk) then

      if rst = '1' then
        o_done <= '0';
        o_M    <= (others => '0');
        o_K    <= (others => (others => '0'));

      else
        o_done <= '0';

        if start = '1' then
          M_total := to_unsigned(1, 2*INT_WIDTH);

          for i in 0 to NUM_MODULI-1 loop
            m_i := to_integer(i_moduli(i));
            M_total := resize(M_total * to_unsigned(m_i, 2*INT_WIDTH), 2*INT_WIDTH);
          end loop;

          o_M <= M_total(INT_WIDTH-1 downto 0);

          for i in 0 to NUM_MODULI-1 loop
            m_i   := to_integer(i_moduli(i));
            Mi    := M_total / to_unsigned(m_i, 2*INT_WIDTH); -- Mi = M / mi
            inv_i := mod_inverse(to_integer(Mi mod to_unsigned(m_i,2*INT_WIDTH)), m_i); -- inv_i = (Mi mod mi)^-1 mod mi
			
            o_K(i) <= resize(Mi * to_unsigned(inv_i, 2*INT_WIDTH), INT_WIDTH);
          end loop;

          o_done <= '1';
        end if;
      end if;
    end if;
  end process;

end RTL;