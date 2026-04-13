-- Підключення необхідних бібліотек: ввід/вивід, семафори GNAT, списки та рядки
with Ada.Text_IO; 
use Ada.Text_IO;
with GNAT.Semaphores; 
use GNAT.Semaphores;
with Ada.Containers.Indefinite_Doubly_Linked_Lists;
use Ada.Containers;
with Ada.Strings;
with Ada.Strings.Fixed;

procedure Task1 is
   -- Ініціалізація двозв'язного списку для зберігання рядків (наше сховище)
   package String_Lists is new Indefinite_Doubly_Linked_Lists (String);
   use String_Lists;

   -- Допоміжна функція для форматування виводу чисел (видаляє зайві пробіли)
   function Fmt (N : Integer) return String is
   begin
      return Ada.Strings.Fixed.Trim (Integer'Image(N), Ada.Strings.Left);
   end Fmt;

   procedure Starter (Storage_Size : Integer; Total_Items : Integer; Num_Producers : Integer; Num_Consumers : Integer) is
      Storage : List; -- Спільний ресурс (сховище)

      -- СЕМАФОРИ ДЛЯ СИНХРОНІЗАЦІЇ:
      -- 1. Access_Storage: М'ютекс (місткість 1), гарантує ексклюзивний доступ до списку
      Access_Storage : Counting_Semaphore (1, Default_Ceiling);
      
      -- 2. Full_Storage: Контролює наявність вільних місць у сховищі. Початкове значення = Storage_Size
      Full_Storage   : Counting_Semaphore (Storage_Size, Default_Ceiling);
      
      -- 3. Empty_Storage: Контролює наявність вироблених товарів. Початкове значення = 0 (сховище порожнє)
      Empty_Storage  : Counting_Semaphore (0, Default_Ceiling);

      -- ОГОЛОШЕННЯ ТИПІВ ЗАДАЧ (аналог класів-потоків у Java/C#)
      -- Використовуємо дві точки входу, щоб розділити передачу параметрів та фактичний запуск
      task type Producer_Task is
         entry Init (Id : Integer; Items_To_Produce : Integer); -- Точка для передачі даних
         entry Go;                                              -- Точка для команди "Старт"
      end Producer_Task;

      task type Consumer_Task is
         entry Init (Id : Integer; Items_To_Consume : Integer);
         entry Go;
      end Consumer_Task;

      -- РЕАЛІЗАЦІЯ ЗАДАЧІ ВИРОБНИКА
      task body Producer_Task is
         My_Id, My_Items : Integer;
      begin
         -- Етап 1: Отримуємо власні параметри і призупиняємось
         accept Init (Id : Integer; Items_To_Produce : Integer) do
            My_Id := Id;
            My_Items := Items_To_Produce;
         end Init;

         -- Етап 2: Чекаємо команди на загальний старт від головного потоку
         accept Go; 

         -- Основний робочий цикл Виробника
         for I in 1 .. My_Items loop
            Full_Storage.Seize;   -- Чекаємо, поки у сховищі з'явиться вільне місце
            Access_Storage.Seize; -- Блокуємо сховище (щоб інші потоки не могли його змінити одночасно)

            declare
               -- Створюємо "підписаний" товар (із зазначенням автора)
               Item_Str : constant String := "Item-" & Fmt(I) & " (from P" & Fmt(My_Id) & ")";
            begin
               Storage.Append (Item_Str); -- Додаємо у сховище
               Put_Line ("[+] Producer " & Fmt(My_Id) & " ADDED: " & Item_Str & " | In storage: " & Fmt(Integer(Storage.Length)));
            end;

            Access_Storage.Release; -- Звільняємо блокування сховища
            Empty_Storage.Release;  -- Сигналізуємо Споживачам, що з'явився новий товар

            delay 0.1; -- Імітація часу на виробництво
         end loop;
      end Producer_Task;

      -- РЕАЛІЗАЦІЯ ЗАДАЧІ СПОЖИВАЧА
      task body Consumer_Task is
         My_Id, My_Items : Integer;
      begin
         -- Етап 1: Отримуємо власні параметри
         accept Init (Id : Integer; Items_To_Consume : Integer) do
            My_Id := Id;
            My_Items := Items_To_Consume;
         end Init;

         -- Етап 2: Чекаємо команди на загальний старт
         accept Go;

         -- Основний робочий цикл Споживача
         for I in 1 .. My_Items loop
            Empty_Storage.Seize;  -- Чекаємо, поки у сховищі з'явиться хоча б один товар
            Access_Storage.Seize; -- Блокуємо сховище

            declare
               -- Читаємо перший елемент зі списку
               Item_Str : constant String := First_Element (Storage);
            begin
               Storage.Delete_First; -- Вилучаємо товар
               Put_Line ("[-] Consumer " & Fmt(My_Id) & " TOOK: " & Item_Str & " | In storage: " & Fmt(Integer(Storage.Length)));
            end;

            Access_Storage.Release; -- Звільняємо блокування сховища
            Full_Storage.Release;   -- Сигналізуємо Виробникам, що звільнилося місце

            delay 0.15; -- Імітація часу на споживання
         end loop;
      end Consumer_Task;

      -- Створення масивів задач (це автоматично створює потоки в пам'яті)
      Producers : array (1 .. Num_Producers) of Producer_Task;
      Consumers : array (1 .. Num_Consumers) of Consumer_Task;

      -- Змінні для розрахунку квот (базова кількість та залишок від ділення)
      P_Base, P_Rem, C_Base, C_Rem, P_Items, C_Items : Integer;

   begin
      Put_Line ("-----------------------------------");
      Put_Line ("STARTING. Storage size: " & Fmt(Storage_Size) & ", Total Items: " & Fmt(Total_Items));
      Put_Line ("-----------------------------------");

      -- ЛОГІКА РОЗПОДІЛУ: Рівномірно ділимо загальну кількість продукції між Виробниками
      P_Base := Total_Items / Num_Producers;
      P_Rem  := Total_Items mod Num_Producers;
      
      for I in 1 .. Num_Producers loop
         if I <= P_Rem then P_Items := P_Base + 1; else P_Items := P_Base; end if;
         Put_Line ("Producer " & Fmt(I) & " will produce: " & Fmt(P_Items));
         
         Producers(I).Init(I, P_Items); -- Передаємо завдання (але потік ще чекає на `Go`)
      end loop;

      -- ЛОГІКА РОЗПОДІЛУ: Рівномірно ділимо продукцію між Споживачами
      C_Base := Total_Items / Num_Consumers;
      C_Rem  := Total_Items mod Num_Consumers;
      
      for I in 1 .. Num_Consumers loop
         if I <= C_Rem then C_Items := C_Base + 1; else C_Items := C_Base; end if;
         Put_Line ("Consumer " & Fmt(I) & " will consume: " & Fmt(C_Items));
         
         Consumers(I).Init(I, C_Items); -- Передаємо завдання (але потік ще чекає на `Go`)
      end loop;

      Put_Line ("-----------------------------------");

      -- СИГНАЛ ДО СТАРТУ: Тепер, коли консоль чиста і всі налаштовані,
      -- масово даємо команду "Go" всім потокам одночасно.
      for I in 1 .. Num_Producers loop
         Producers(I).Go;
      end loop;

      for I in 1 .. Num_Consumers loop
         Consumers(I).Go;
      end loop;

      -- Процедура Starter автоматично зупиниться на цьому місці (невидимий бар'єр),
      -- поки всі дочірні задачі з масивів Producers та Consumers не завершать свою роботу.
   end Starter;

begin
   Starter (Storage_Size => 10, Total_Items => 8, Num_Producers => 1, Num_Consumers => 4);
   Put_Line ("-----------------------------------");
   Put_Line ("Work is successfully completed! All items produced and consumed.");
end Task1;