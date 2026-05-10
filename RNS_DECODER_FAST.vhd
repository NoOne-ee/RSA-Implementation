library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RNS_PKG.all;

entity RNS_DECODER_FAST is
  port(
    i_rns : in  mod_array_t(0 to NUM_MODULI-1);
    i_K   : in  crt_array_t(0 to NUM_MODULI-1);
    i_M   : in  unsigned(INT_WIDTH-1 downto 0);

    o_x   : out unsigned(INT_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RNS_DECODER_FAST is
begin

  process(i_rns, i_k, i_M)
    variable sum_v : unsigned(2*INT_WIDTH-1 downto 0);
    variable M_v   : unsigned(2*INT_WIDTH-1 downto 0);
  begin
    sum_v := (others => '0');
    M_v   := resize(i_M, 2*INT_WIDTH);

    for i in 0 to NUM_MODULI-1 loop
        sum_v := sum_v + resize(resize(i_rns(i) , 2*INT_WIDTH) * resize(i_K(i), 2*INT_WIDTH), 2*INT_WIDTH);
    end loop;

    if M_v /= 0 then
        o_x <= resize(sum_v mod M_v, INT_WIDTH);
    else
        o_x <= (others => '0');
    end if;
  end process;

end RTL;