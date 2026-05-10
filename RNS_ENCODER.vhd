library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RNS_PKG.all;
 
entity RNS_ENCODER is      
     port(
        i_x       : in unsigned(INT_WIDTH-1 downto 0);
        i_moduli  : in mod_array_t (0 to NUM_MODULI-1);
        o_RNS_OUT : out mod_array_t (0 to NUM_MODULI-1)
     );
end entity;

architecture rtl of RNS_ENCODER is
begin
      
    process(i_x, i_moduli)
        variable remainder : unsigned(INT_WIDTH-1 downto 0);
        variable mod_reg   : unsigned(INT_WIDTH-1 downto 0);
    begin
        for i in 0 to NUM_MODULI-1 loop
            if i_moduli(i) = 0 then
                o_RNS_OUT(i) <= (others => '0');
            else
			    mod_reg   := resize(i_moduli(i), INT_WIDTH);
                remainder := (others => '0');
				
				for j in INT_WIDTH-1 downto 0 loop
				    remainder    := shift_left(remainder, 1);
					remainder(0) := i_x(j);
					if  remainder >= mod_reg then
					    remainder :=  remainder - mod_reg;
                    end if;
				end loop;
				
                o_RNS_OUT(i) <= resize(remainder, MOD_WIDTH);
            end if;
        end loop;
    end process;
	
end rtl;