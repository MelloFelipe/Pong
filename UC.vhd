library ieee;
use ieee.std_logic_1164.all;

entity UC is
  port (    
    CLOCK_50                  : in  std_logic;
  --KEY                       : in  std_logic_vector(0 downto 0);
    key_on                    : in	std_logic_vector(2 downto 0);
    key_code                  : in	std_logic_vector(47 downto 0);
    VGA_R, VGA_G, VGA_B       : out std_logic_vector(7 downto 0);
    VGA_HS, VGA_VS            : out std_logic;
    VGA_BLANK_N, VGA_SYNC_N   : out std_logic;
    VGA_CLK                   : out std_logic
    );
end UC;

architecture comportamento of UC is
  
  signal rstn : std_logic;              -- reset active low para nossos
                                        -- circuitos sequenciais.

  -- Interface com a memória de vídeo do controlador

  signal we : std_logic;                        -- write enable ('1' p/ escrita)
  signal addr : integer range 0 to 12287;       -- endereco mem. vga
  signal pixel : std_logic_vector(2 downto 0);  -- valor de cor do pixel
  signal pixel_bit : std_logic;                 -- um bit do vetor acima

  -- Sinais dos contadores de linhas e colunas utilizados para percorrer
  -- as posições da memória de vídeo (pixels) no momento de construir um quadro.
  
  signal line : integer range 0 to 95;  -- linha atual
  signal col : integer range 0 to 127;  -- coluna atual

  signal col_rstn : std_logic;          -- reset do contador de colunas
  signal col_enable : std_logic;        -- enable do contador de colunas

  signal line_rstn : std_logic;          -- reset do contador de linhas
  signal line_enable : std_logic;        -- enable do contador de linhas

  signal fim_escrita : std_logic;       -- '1' quando um quadro terminou de ser
                                        -- escrito na memória de vídeo

  -- Sinais que armazem a posição de uma bola, que deverá ser desenhada
  -- na tela de acordo com sua posição.

  signal pos_bola_x : integer range 0 to 127 := 64;  -- coluna atual da bola
  signal pos_bola_y : integer range 0 to 95  := 80;  -- linha atual da bola

  signal atualiza_pos_bola_x : std_logic;    -- se '1' = bola muda sua pos. no eixo x
  signal atualiza_pos_bola_y : std_logic;    -- se '1' = bola muda sua pos. no eixo y

  signal derivada_bola : integer range -3 to 3 := 1; -- angulo da direcao da bola
  -- derivada_bola_bola = 0: angulo de 0            graus em relacao ao eixo x
  -- derivada_bola_bola = 1: angulo de +-45         graus em relacao ao eixo x
  -- derivada_bola_bola = 2: angulo de +-63.435     graus em relacao ao eixo x
  -- derivada_bola_bola = 3: angulo de +-71.5650512 graus em relacao ao eixo x
  
  -- Especificação dos tipos e sinais da máquina de estados de controle
  type estado_t is (inicio_jogo, inicio_partida, constroi_quadro, move_bola_e_PADs, reseta_partida, game_over);
  signal estado: estado_t := inicio_jogo;
  signal proximo_estado: estado_t := inicio_jogo;

  -- Sinais para um contador utilizado para atrasar a atualização da
  -- posição da bola, a fim de evitar que a animação fique excessivamente
  -- veloz. Aqui utilizamos um contador de 0 a 1250000, de modo que quando
  -- alimentado com um clock de 50MHz, ele demore 25ms (40fps) para contar até o final.
  
  signal contador : integer range 0 to 1250000 - 1 := 0;  -- contador
  signal timer : std_logic;        -- vale '1' quando o contador chegar ao fim
  signal timer_rstn, timer_enable : std_logic;
  
  signal sync, blank: std_logic;

  -- Sinais para controlar o movimento dos PAD's
  -- PAD tem o seu tamanho definido como 7 pixels
  signal pos_PAD1 : integer range 3 to 92 := 47;   -- linha atual do pixel central do PAD1
  signal pos_PAD2 : integer range 3 to 92 := 47;   -- linha atual do pixel central do PAD2

  signal atualiza_pos_PADs : std_logic;    -- se '1' = PAD1 e PAD2 muda sua pos. no eixo y
  
  signal ponto: std_logic := '0'; -- '1' quando um ponto foi marcado
  signal pontos_PAD1 : integer range 0 to 7 := 0;   -- pontos marcados pelo PAD1
  signal pontos_PAD2 : integer range 0 to 7 := 0;   -- pontos marcados pelo PAD2
  
  signal flag_inicio : std_logic := '0'; -- verifica se o jogo foi iniciado
  signal flag_inicio_rstn : std_logic := '1'; -- reseta valor da flag, ativo em baixo
  -- O QUE FALTA:
  -- Implementar a contrucao de todas as telas (inicio, partida, reseta_partida e game_over), talvez a construcao da bola e dos PADs ja esteja 10/10
  
  -- ideia para deixar mais bonito: na maquina de estados, zerar tudo antes do case e so alterar para 1 dentro do case (igual ao lab10), na verdade talvez isso de problemas
  
begin  -- comportamento


  -- Aqui instanciamos o controlador de vídeo, 128 colunas por 96 linhas
  -- (aspect ratio 4:3). Os sinais que iremos utilizar para comunicar
  -- com a memória de vídeo (para alterar o brilho dos pixels) são
  -- write_clk (nosso clock), write_enable ('1' quando queremos escrever
  -- o valor de um pixel), write_addr (endereço do pixel a escrever)
  -- e data_in (valor do brilho do pixel RGB, 1 bit pra cada componente de cor)
  vga_controller: entity work.vgacon port map (
    clk50M       => CLOCK_50,
    rstn         => '1',
    red          => VGA_R,
    green        => VGA_G,
    blue         => VGA_B,
    hsync        => VGA_HS,
    vsync        => VGA_VS,
    write_clk    => CLOCK_50,
    write_enable => we,
    write_addr   => addr,
    data_in      => pixel,
    vga_clk      => VGA_CLK,
    sync         => sync,
    blank        => blank);
  VGA_SYNC_N <= NOT sync;
  VGA_BLANK_N <= NOT blank;

  -----------------------------------------------------------------------------
  -- Processos que controlam contadores de linhas e coluna para varrer
  -- todos os endereços da memória de vídeo, no momento de construir um quadro.
  -----------------------------------------------------------------------------

  -- purpose: Este processo conta o número da coluna atual, quando habilitado
  --          pelo sinal "col_enable".
  -- type   : sequential
  -- inputs : CLOCK_50, col_rstn
  -- outputs: col
  conta_coluna: process (CLOCK_50, col_rstn)
  begin  -- process conta_coluna
    if col_rstn = '0' then                  -- asynchronous reset (active low)
      col <= 0;
    elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      if col_enable = '1' then
        if col = 127 then               -- conta de 0 a 127 (128 colunas)
          col <= 0;
        else
          col <= col + 1;  
        end if;
      end if;
    end if;
  end process conta_coluna;
    
  -- purpose: Este processo conta o número da linha atual, quando habilitado
  --          pelo sinal "line_enable".
  -- type   : sequential
  -- inputs : CLOCK_50, line_rstn
  -- outputs: line
  conta_linha: process (CLOCK_50, line_rstn)
  begin  -- process conta_linha
    if line_rstn = '0' then                  -- asynchronous reset (active low)
      line <= 0;
    elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      -- o contador de linha só incrementa quando o contador de colunas
      -- chegou ao fim (valor 127)
      if line_enable = '1' and col = 127 then
        if line = 95 then               -- conta de 0 a 95 (96 linhas)
          line <= 0;
        else
          line <= line + 1;  
        end if;        
      end if;
    end if;
  end process conta_linha;

  -- Este sinal é útil para informar nossa lógica de controle quando
  -- o quadro terminou de ser escrito na memória de vídeo, para que
  -- possamos avançar para o próximo estado.
  fim_escrita <= '1' when (line = 95) and (col = 127)
                 else '0'; 
				 
  -----------------------------------------------------------------------------
  -- Processo que verifica se o jogo deve ser iniciado
  verifica_inicio: process(CLOCK_50)
  begin
	if rising_edge(CLOCK_50) then
		if flag_inicio_rstn = '0' then
			flag_inicio <= '0';
		end if;
		if flag_inicio <= '0' then
			if key_code(15 downto 0) = x"005A" then -- se a tecla "ENTER" for pressionada
				flag_inicio <= '1';
			end if;
		end if;
	end if;
  end process verifica_inicio;
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- Abaixo estão processos relacionados com a atualização da posição da
  -- bola e dos PAD's. Todos são controlados por sinais de enable de modo que a posição
  -- só é de fato atualizada quando o controle (uma máquina de estados)
  -- solicitar.
  -----------------------------------------------------------------------------

  -- purpose: Este processo irá atualizar a coluna atual da bola,
  --          alterando sua posição no próximo quadro a ser desenhado.
  -- type   : sequential
  -- inputs : CLOCK_50, rstn
  -- outputs: pos_bola_x
  p_atualiza_pos_bola_x: process (CLOCK_50, rstn)
    type direcao_t is (direita, esquerda);
    variable direcao : direcao_t := direita;
  begin  -- process p_atualiza_pos_bola_x
    if rstn = '0' then                  -- asynchronous reset (active low)
      pos_bola_x <= 0;
    elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      if atualiza_pos_bola_x = '1' then
        if direcao = direita then         
          if pos_bola_x = 127 then -- bola pode chegar na fronteira
				if abs(pos_bola_y - pos_PAD2) < 4 then -- verificar se o PAD2 está na linha onde a bola pode chegar
					direcao := esquerda;
					derivada_bola <= pos_bola_y - pos_PAD2; -- calculo da nova derivada_bola
				else
					pontos_PAD1 <= pontos_PAD1 + 1; -- mais um ponto para o PAD1
				   pos_bola_x <= 64;
				   --pos_bola_y <= 80;
				   derivada_bola <= -1;
				end if;    
          else
            pos_bola_x <= pos_bola_x + 1;
          end if;        
        else  -- se a direcao é esquerda
          if pos_bola_x = 0 then
				if abs(pos_bola_y - pos_PAD1) < 4 then
					direcao := direita;
					derivada_bola <= pos_bola_y - pos_PAD1;
				else
					pontos_PAD2 <= pontos_PAD2 + 1; -- mais um ponto para o PAD2
					pos_bola_x <= 64;
		         --pos_bola_y <= 80;
		         derivada_bola <= -1;
				end if;
          else
            pos_bola_x <= pos_bola_x - 1;
          end if;
        end if;
      end if;
    end if;
  end process p_atualiza_pos_bola_x;

  -- purpose: Este processo irá atualizar a linha atual da bola,
  --          alterando sua posição no próximo quadro a ser desenhado.
  -- type   : sequential
  -- inputs : CLOCK_50, rstn
  -- outputs: pos_bola_y
  p_atualiza_pos_bola_y: process (CLOCK_50, rstn)
    type direcao_t is (desce, sobe);
    variable direcao : direcao_t := desce;
  begin  -- process p_atualiza_pos_bola_x
    if rstn = '0' then                  -- asynchronous reset (active low)
      pos_bola_y <= 0; -- talvez mudar para 80
    elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      if atualiza_pos_bola_y = '1' then
        if direcao = desce then         
          if pos_bola_y = 95 then
            direcao := sobe;  
          else
            --pos_bola_y <= pos_bola_y + 1;
				if derivada_bola > 0 then -- se bateu na parte de cima do PAD
					direcao := sobe;
				else -- se bateu na parte de baixo do PAD
					if (pos_bola_y - derivada_bola) > 95 then -- se sair dos limites
						pos_bola_y <= 95;
					else
						pos_bola_y <= pos_bola_y - derivada_bola; -- subtracao, pois derivada_bola é < 0
					end if;
			   end if;
          end if;        
        else  -- se a direcao é para subir
          if pos_bola_y = 0 then
            direcao := desce;
          else
            --pos_bola_y <= pos_bola_y - 1;
				if derivada_bola < 0 then -- se bateu na parte de baixo do PAD
					direcao := desce;
				else -- se bateu na parte de cima do PAD
					if (pos_bola_y - derivada_bola) < 0 then -- se sair dos limites
						pos_bola_y <= 0;
					else
						pos_bola_y <= pos_bola_y - derivada_bola; -- subtracao, pois derivada_bola é > 0
					end if;
				end if;
          end if;
        end if;
      end if;
    end if;
  end process p_atualiza_pos_bola_y;
  
  -- purpose: Este processo irá atualizar a posicao dos PAD's
  -- type   : sequential
  -- inputs : CLOCK_50
  -- outputs: pos_PAD1 e pos_PAD2
  p_atualiza_pos_PADs: process (CLOCK_50) -- talvez mudar para key_on
  begin
    if CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      if atualiza_pos_PADs = '1' then
			if key_code(15 downto 0) = x"E075" or key_code(31 downto 16) = x"E075"
		   or key_code(47 downto 32) = x"E075"	then -- Up arrow pressionada
				if pos_PAD1 > 3 then -- PAD1 nao está no limite superior
					pos_PAD1 <= pos_PAD1 + 1;
				end if;
			end if;
			if key_code(15 downto 0) = x"E072" or key_code(31 downto 16) = x"E072"
		   or key_code(47 downto 32) = x"E072"	then -- Down arrow pressionada
				if pos_PAD1 < 92 then -- PAD1 nao está no limite inferior
					pos_PAD1 <= pos_PAD1 - 1;
				end if;
			end if;
			if key_code(15 downto 0) = x"001D" or key_code(31 downto 16) = x"001D"
		   or key_code(47 downto 32) = x"001D"	then -- tecla 'W' pressionada
				if pos_PAD2 > 3 then -- PAD2 nao está no limite superior
					pos_PAD2 <= pos_PAD2 + 1;
				end if;
			end if;
			if key_code(15 downto 0) = x"001B" or key_code(31 downto 16) = x"001B"
		   or key_code(47 downto 32) = x"001B"	then -- tecla 'S' pressionada
				if pos_PAD2 < 92 then -- PAD2 nao está no limite inferior
					pos_PAD2 <= pos_PAD2 - 1;
				end if;
			end if;
      end if;
	end if;
  end process p_atualiza_pos_PADs;
  
   -----------------------------------------------------------------------------
  -- Brilho do pixel
  -----------------------------------------------------------------------------
  -- O brilho do pixel é branco quando os contadores de linha e coluna, que
  -- indicam o endereço do pixel sendo escrito para o quadro atual, casam com a
  -- posição da bola (sinais pos_bola_x e pos_bola_y) ou com a posição dos PADs.
  -- Caso contrário, o pixel é preto.

--  pixel_bit <= '1' when ((col = pos_bola_x) and (line = pos_bola_y)) 
--					or ((abs(line-pos_PAD1) < 4) and col = 0)
--					or ((abs(line-pos_PAD2) < 4) and col = 127) else '0';

	process(CLOCK_50)
	  begin
		 if CLOCK_50'event and CLOCK_50 = '1' then
			case estado is
			  when inicio_jogo    => pixel_bit <= '0';
										  
			  when inicio_partida => if ((col = pos_bola_x) and (line = pos_bola_y)) 
												 or ((abs(line-pos_PAD1) < 4) and col = 0)
												 or ((abs(line-pos_PAD2) < 4) and col = 127) then
												pixel_bit <= '1';
											 else
												pixel_bit <= '0';
											 end if;

			  when game_over      => pixel_bit <= '0';
			
			  when others         => pixel_bit <= pixel_bit;
			  
			end case;
		 end if;
	  end process;
	  
  pixel <= (others => pixel_bit);
  
  -- O endereço de memória pode ser construído com essa fórmula simples,
  -- a partir da linha e coluna atual
  addr  <= col + (128 * line);
  
  -----------------------------------------------------------------------------
  -- Processos que definem a FSM (finite state machine), nossa máquina
  -- de estados de controle.
  -----------------------------------------------------------------------------

  -- purpose: Esta é a lógica combinacional que calcula sinais de saída a partir
  --          do estado atual e alguns sinais de entrada (Máquina de Mealy).
  -- type   : combinational
  -- inputs : estado, fim_escrita, timer
  -- outputs: proximo_estado, atualiza_pos_bola_x, atualiza_pos_bola_y, line_rstn,
  --          line_enable, col_rstn, col_enable, we, timer_enable, timer_rstn
  logica_mealy: process (estado, fim_escrita, timer, flag_inicio)
  begin  -- process logica_mealy
    case estado is
		when inicio_jogo    => if timer = '1' then
									    if flag_inicio = '1' then
										   proximo_estado <= inicio_partida;
									    else
                                 proximo_estado <= constroi_quadro;
										 end if;
                             else
                               proximo_estado <= inicio_jogo;
                             end if;
                             atualiza_pos_bola_x <= '0';
                             atualiza_pos_bola_y <= '0';
									  atualiza_pos_PADs   <= '0';
                             line_rstn      <= '0';  -- reset é active low!
                             line_enable    <= '0';
                             col_rstn       <= '0';  -- reset é active low!
                             col_enable     <= '0';
                             we             <= '0';
                             timer_rstn     <= '1';  -- reset é active low!
                             timer_enable   <= '1';
									  
      when inicio_partida    => if timer = '1' then              
                               proximo_estado <= constroi_quadro;
                             else
                               proximo_estado <= inicio_partida;
                             end if;
                             atualiza_pos_bola_x <= '0';
                             atualiza_pos_bola_y <= '0';
									  atualiza_pos_PADs   <= '0';
                             line_rstn      <= '0';  -- reset é active low!
                             line_enable    <= '0';
                             col_rstn       <= '0';  -- reset é active low!
                             col_enable     <= '0';
                             we             <= '0';
                             timer_rstn     <= '1';  -- reset é active low!
                             timer_enable   <= '1';

      when constroi_quadro=> if fim_escrita = '1' then
                               proximo_estado <= move_bola_e_PADs;
                             else
                               proximo_estado <= constroi_quadro;
                             end if;
                             atualiza_pos_bola_x <= '0';
                             atualiza_pos_bola_y <= '0';
									  atualiza_pos_PADs   <= '0';
                             line_rstn      <= '1';
                             line_enable    <= '1';
                             col_rstn       <= '1';
                             col_enable     <= '1';
                             we             <= '1';
                             timer_rstn     <= '0'; 
                             timer_enable   <= '0';

      when move_bola_e_PADs=>proximo_estado <= inicio_partida;
                             atualiza_pos_bola_x <= '1';
                             atualiza_pos_bola_y <= '1';
									  atualiza_pos_PADs   <= '1';
                             line_rstn      <= '1';
                             line_enable    <= '0';
                             col_rstn       <= '1';
                             col_enable     <= '0';
                             we             <= '0';
                             timer_rstn     <= '0'; 
                             timer_enable   <= '0';
		
		when reseta_partida => if (pontos_PAD1 < 7) and (pontos_PAD2 < 7) then
		                         proximo_estado <= inicio_partida;
									  else
									    proximo_estado <= game_over;
									  end if;
		                       --pontuacao_enable <= '1';
									  atualiza_pos_bola_x <= '0';
                             atualiza_pos_bola_y <= '0';
									  atualiza_pos_PADs   <= '0';
                             line_rstn      <= '1';
                             line_enable    <= '1';
                             col_rstn       <= '1';
                             col_enable     <= '1';
                             we             <= '1';
                             timer_rstn     <= '0'; 
                             timer_enable   <= '0';
		
      when others         => proximo_estado <= inicio_partida;
                             atualiza_pos_bola_x <= '0';
                             atualiza_pos_bola_y <= '0';
									  atualiza_pos_PADs   <= '0';
                             line_rstn      <= '1';
                             line_enable    <= '0';
                             col_rstn       <= '1';
                             col_enable     <= '0';
                             we             <= '0';
                             timer_rstn     <= '1'; 
                             timer_enable   <= '0';
      
    end case;
  end process logica_mealy;
  
  -- purpose: Avança a FSM para o próximo estado
  -- type   : sequential
  -- inputs : CLOCK_50, rstn, proximo_estado
  -- outputs: estado
  seq_fsm: process (CLOCK_50, rstn)
  begin  -- process seq_fsm
    if rstn = '0' then                  -- asynchronous reset (active low)
      estado <= inicio_partida;
    elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      estado <= proximo_estado;
    end if;
  end process seq_fsm;

  -----------------------------------------------------------------------------
  -- Processos do contador utilizado para atrasar a animação (evitar
  -- que a atualização de quadros fique excessivamente veloz).
  -----------------------------------------------------------------------------
  -- purpose: Incrementa o contador a cada ciclo de clock
  -- type   : sequential
  -- inputs : CLOCK_50, timer_rstn
  -- outputs: contador, timer
  p_contador: process (CLOCK_50, timer_rstn)
  begin  -- process p_contador
    if timer_rstn = '0' then            -- asynchronous reset (active low)
      contador <= 0;
    elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      if timer_enable = '1' then       
        if contador = 1250000 - 1 then
          contador <= 0;
        else
          contador <=  contador + 1;        
        end if;
      end if;
    end if;
  end process p_contador;

  -- purpose: Calcula o sinal "timer" que indica quando o contador chegou ao
  --          final
  -- type   : combinational
  -- inputs : contador
  -- outputs: timer
  p_timer: process (contador)
  begin  -- process p_timer
    if contador = 1250000 - 1 then
      timer <= '1';
    else
      timer <= '0';
    end if;
  end process p_timer;

  -----------------------------------------------------------------------------
  -- Processos que sincronizam sinais assíncronos, de preferência com mais
  -- de 1 flipflop, para evitar metaestabilidade.
  -----------------------------------------------------------------------------
  
  -- purpose: Aqui sincronizamos nosso sinal de reset vindo do botão da DE1
  -- type   : sequential
  -- inputs : CLOCK_50
  -- outputs: rstn
--  build_rstn: process (CLOCK_50)
--    variable temp : std_logic;          -- flipflop intermediario
--  begin  -- process build_rstn
--    if CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
--      rstn <= temp;
--      temp := KEY(0);      
--    end if;
--  end process build_rstn;

  
end comportamento;
