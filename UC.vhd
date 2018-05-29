LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE work.UC_pack.ALL;

ENTITY UC IS
	PORT (
		clock			: IN	STD_LOGIC;
		key_on		: IN	STD_LOGIC_VECTOR (2  DOWNTO 0);
   	key_code	   : IN	STD_LOGIC_VECTOR (47 DOWNTO 0);
		--IR_Ld, PC_Inc, ALU_2_DBus, DM_Rd, DM_Wr, PC_Ld_En, Reg_2_IO, IO_2_Reg, Reg_Wr, Stat_Wr, DM_2_DBus: OUT	STD_LOGIC		
	);
END ENTITY;

ARCHITECTURE Behavior OF UC IS

	COMPONENT constroi_quadro
	port (
		 clock        : in std_logic;
		 current_state: in states_UC;
		 VGA_R, VGA_G, VGA_B    : out std_logic_vector(7 downto 0);
		 VGA_HS, VGA_VS         : out std_logic;
		 VGA_BLANK_N, VGA_SYNC_N: out std_logic;
		 VGA_CLK                : out std_logic
		 );
	END COMPONENT;
	SIGNAL current_state : states_UC := INICIO;
  
BEGIN
	StateMachine:
	PROCESS (clock, key_on, current_state)
	BEGIN
		IF (clock'EVENT AND clock = '1') THEN
			-- Talvez zerar alguns sinais aqui
			
			CASE current_state IS
			
				WHEN INICIO =>
					IF key_on(0) = '1' THEN
						IF key_code(15 downto 0) = "005A" THEN-- Enter
							current_state <= INICIO_PARTIDA;
						END IF;
					END IF;
          
				WHEN INICIO_PARTIDA =>
          
				WHEN PARTIDA =>
					CASE key_on IS
						WHEN "000" =>

						WHEN "001" =>

						WHEN "010" =>

						WHEN "011" =>

						WHEN "100" =>

						WHEN "101" =>

						WHEN "110" =>

						WHEN OTHERS =>

					END CASE;			
			END CASE;
		END IF;
	END PROCESS;
	
	DefineTela: constroi_quadro PORT MAP(clock, current_state, 
	
END ARCHITECTURE;
