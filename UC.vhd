LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

LIBRARY Processor;
USE Processor.Processor_pack.ALL;

ENTITY UC IS
	PORT (
		clock			: IN	STD_LOGIC;
		key_on		: IN	STD_LOGIC_VECTOR (2 DOWNTO 0);
   	        key_code	: in	std_logic_vector(47 downto 0);
		--IR_Ld, PC_Inc, ALU_2_DBus, DM_Rd, DM_Wr, PC_Ld_En, Reg_2_IO, IO_2_Reg, Reg_Wr, Stat_Wr, DM_2_DBus: OUT	STD_LOGIC		
	);
END ENTITY;

ARCHITECTURE Behavior OF UC IS

  TYPE states_UC IS (INICIO, INICIO_PARTIDA, PARTIDA, GAME_OVER);
	SIGNAL current_state : states_UC := INICIO;
  
BEGIN
	StateMachine:
	PROCESS (clock, key_on, current_state)
	BEGIN
		IF (clock'EVENT AND clock = '1') THEN
			-- Talvez zerar alguns sinais aqui
			
			CASE current_state IS
			
				WHEN INICIO => 
          				current_state <= INICIO_PARTIDA;
          
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
END ARCHITECTURE;
