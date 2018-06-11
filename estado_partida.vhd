library ieee;
use ieee.std_logic_1164.all;

entity estado_partida is
  port (
	atualiza_pos_bola_x, atualiza_pos_bola_y: in std_logic;
	flag_inicio: in std_logic;
	pos_PAD1 :   in integer range 3 to 92;   
   pos_PAD2 :   in integer range 3 to 92;   
	pontos_PAD1, pontos_PAD2: out integer range 0 to 7;
	pos_bola_x: out integer range 0 to 127;
	pos_bola_y: out integer range 0 to 95
    );
end estado_partida;

architecture structure of estado_partida is
  
  signal pos_bola_x_local : integer range 0 to 127 := 64;  -- coluna atual da bola
  signal pos_bola_y_local : integer range 0 to 95:= 47;  -- linha atual da bola
  
  signal derivada_bola : integer range -3 to 3 := 0; -- angulo da direcao da bola
  -- derivada_bola_bola = 0: angulo de 0            graus em relacao ao eixo x
  -- derivada_bola_bola = 1: angulo de +-45         graus em relacao ao eixo x
  -- derivada_bola_bola = 2: angulo de +-63.435     graus em relacao ao eixo x
  -- derivada_bola_bola = 3: angulo de +-71.5650512 graus em relacao ao eixo x
  
  signal pontos_PAD1_local : integer range 0 to 7:= 0;   -- pontos marcados pelo PAD1
  signal pontos_PAD2_local : integer range 0 to 7:= 0;   -- pontos marcados pelo PAD2
  
begin  -- structure

	-----------------------------------------------------------------------------
  -- Abaixo estão processos relacionados com a atualização da posição da
  -- bola e dos PAD's. Todos são controlados por sinais de enable de modo que a posição
  -- só é de fato atualizada quando o controle (uma máquina de estados)
  -- solicitar.
  -----------------------------------------------------------------------------

  -- purpose: Este processo irá atualizar a coluna atual da bola,
  --          alterando sua posição no próximo quadro a ser desenhado.
  -- type   : sequential
  -- inputs : CLOCK_50
  -- outputs: pos_bola_x_local
  p_atualiza_pos_bola_x: process (atualiza_pos_bola_x, flag_inicio)
    type direcao_t is (direita, esquerda);
    variable direcao : direcao_t := direita;
  begin  -- process p_atualiza_pos_bola_x
    if atualiza_pos_bola_x'event and atualiza_pos_bola_x = '1' then  -- rising clock edge
     -- if atualiza_pos_bola_x = '1' then
			if flag_inicio = '1' and (pontos_PAD1_local >=7 or pontos_PAD2_local >= 7) then
				pontos_PAD1_local <= 0;
				pontos_PAD2_local <= 0;
        elsif direcao = direita then         
          if pos_bola_x_local = 117 then -- bola pode chegar na fronteira
				if abs(pos_bola_y_local - pos_PAD2) < 4 then -- verificar se o PAD2 está na linha onde a bola pode chegar
					direcao := esquerda;
					derivada_bola <= pos_PAD2 - pos_bola_y_local; -- calculo da nova derivada_bola
				else
					pontos_PAD1_local <= pontos_PAD1_local + 1; -- mais um ponto para o PAD1
				   pos_bola_x_local <= 64;
				   derivada_bola <= 0;
				end if;    
          else
            pos_bola_x_local <= pos_bola_x_local + 1;
          end if;        
        else  -- se a direcao é esquerda
          if pos_bola_x_local = 10 then
				if abs(pos_bola_y_local - pos_PAD1) < 4 then
					direcao := direita;
					derivada_bola <= pos_PAD1 - pos_bola_y_local;
				else
					pontos_PAD2_local <= pontos_PAD2_local + 1; -- mais um ponto para o PAD2
					pos_bola_x_local <= 64;
		         derivada_bola <= 0;
				end if;
          else
            pos_bola_x_local <= pos_bola_x_local - 1;
          end if;
        end if;
      --end if;
    end if;
  end process p_atualiza_pos_bola_x;

  -- purpose: Este processo irá atualizar a linha atual da bola,
  --          alterando sua posição no próximo quadro a ser desenhado.
  -- type   : sequential
  -- inputs : CLOCK_50
  -- outputs: pos_bola_y_local
  p_atualiza_pos_bola_y: process (atualiza_pos_bola_y)
    type direcao_t is (desce, sobe);
    variable direcao : direcao_t := desce;
  begin  -- process p_atualiza_pos_bola_x
    if atualiza_pos_bola_y'event and atualiza_pos_bola_y = '1' then  -- rising clock edge
     -- if atualiza_pos_bola_y = '1' then
        if direcao = desce then         
          if pos_bola_y_local >= 95 then
            direcao := sobe;  
          else
				if (pos_bola_y_local - derivada_bola) > 95 or (pos_bola_y_local + derivada_bola) > 95 then -- se sair dos limites
					pos_bola_y_local <= 95;
				else
					if derivada_bola > 0 then
						pos_bola_y_local <= pos_bola_y_local + derivada_bola;
					else
						pos_bola_y_local <= pos_bola_y_local - derivada_bola; -- subtracao, pois derivada_bola é < 0
					end if;
				end if;
          end if;        
        else  -- se a direcao é para subir
          if pos_bola_y_local <= 0 then
            direcao := desce;
          else
				if (pos_bola_y_local - derivada_bola) < 0 or (pos_bola_y_local + derivada_bola) < 0 then -- se sair dos limites
					pos_bola_y_local <= 0;
				else
					if derivada_bola < 0 then
						pos_bola_y_local <= pos_bola_y_local + derivada_bola;
					else
						pos_bola_y_local <= pos_bola_y_local - derivada_bola; -- subtracao, pois derivada_bola é > 0
					end if;
				end if;
          end if;
        end if;
      --end if;
    end if;
  end process p_atualiza_pos_bola_y;
  
  pos_bola_x <= pos_bola_x_local;
  pos_bola_y <= pos_bola_y_local;
  pontos_PAD1 <= pontos_PAD1_local;
  pontos_PAD2 <= pontos_PAD2_local;
 
end structure;
