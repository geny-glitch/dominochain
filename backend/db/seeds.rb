# frozen_string_literal: true

# Chargement des questions du quiz 1000€
quiz_questions_path = Rails.root.join("db", "quiz_questions.yml")
if File.exist?(quiz_questions_path)
  data = YAML.load_file(quiz_questions_path)
  if data.present?
    data.each do |attrs|
      next unless attrs.is_a?(Hash) && attrs["question"].present?

      QuizQuestion.find_or_initialize_by(question: attrs["question"]).tap do |q|
        q.answers = attrs["answers"] || [attrs["answer"]].compact
        q.difficulty = attrs["difficulty"] || "bleu"
        q.category = attrs["category"]
        q.question_type = attrs["question_type"] || "normal"
        q.save!
      end
    end
  end

  # Compléter jusqu'à 500 questions normales si nécessaire
  base = QuizQuestion.normal.to_a
  target = 500
  while QuizQuestion.normal.count < target && base.any?
    q = base.sample
    QuizQuestion.create!(
      question: "#{q.question} [v#{SecureRandom.hex(2)}]",
      answers: q.answers,
      difficulty: %w[bleu blanc rouge].sample,
      category: q.category,
      question_type: "normal"
    )
  end

  # Questions banco et super_banco si absentes
  if QuizQuestion.banco.count < 20
    banco_data = [
      { question: "Quel est le nom du traité signé en 843 qui partage l'empire carolingien ?", answers: ["Verdun", "traité de Verdun"] },
      { question: "Qui a écrit « Les Pensées » ?", answers: ["Pascal", "Blaise Pascal"] },
      { question: "Quelle est la plus ancienne université française encore en activité ?", answers: ["Paris", "université de Paris", "Sorbonne"] },
      { question: "Quel roi a promulgué l'édit de Fontainebleau révoquant l'édit de Nantes ?", answers: ["Louis XIV", "Louis 14"] },
      { question: "Quel compositeur a écrit « L'Art de la fugue » ?", answers: ["Bach", "Jean-Sébastien Bach", "Johann Sebastian Bach"] },
      { question: "Quelle bataille en 52 av. J.-C. a vu la défaite de Vercingétorix ?", answers: ["Alésia", "bataille d'Alésia"] },
      { question: "Qui a peint « L'École d'Athènes » ?", answers: ["Raphaël", "Raffaello Sanzio"] },
      { question: "Quel est le nom du traité qui a mis fin à la guerre de Trente Ans ?", answers: ["Westphalie", "traité de Westphalie", "paix de Westphalie"] },
      { question: "Qui a fondé l'Académie française ?", answers: ["Richelieu", "cardinal de Richelieu"] },
      { question: "Quelle ville italienne a été le berceau de la Renaissance ?", answers: ["Florence", "Firenze"] }
    ]
    banco_data.each do |attrs|
      QuizQuestion.find_or_create_by!(question: attrs[:question]) do |q|
        q.answers = attrs[:answers]
        q.difficulty = "rouge"
        q.question_type = "banco"
      end
    end
  end

  if QuizQuestion.super_banco.count < 20
    super_data = [
      { question: "Quel philosophe présocratique a dit que tout est eau ?", answers: ["Thalès", "Thalès de Milet"] },
      { question: "Quel est le nom du traité qui a créé la CECA en 1951 ?", answers: ["Paris", "traité de Paris"] },
      { question: "Qui a composé « Les Quatre Saisons » ?", answers: ["Vivaldi", "Antonio Vivaldi"] },
      { question: "Quel pape a convoqué le concile de Trente ?", answers: ["Paul III", "Paul 3"] },
      { question: "Quelle est la capitale du Bhoutan ?", answers: ["Thimphou", "Thimphu"] },
      { question: "Qui a écrit « De l'esprit des lois » ?", answers: ["Montesquieu", "Charles de Montesquieu"] },
      { question: "Quel roi wisigoth a été vaincu à Vouillé en 507 ?", answers: ["Alaric II", "Alaric"] },
      { question: "Quelle est la plus petite nation souveraine du monde ?", answers: ["Vatican", "le Vatican"] },
      { question: "Qui a inventé le système de notation musicale moderne ?", answers: ["Guido d'Arezzo", "Guido"] },
      { question: "Quel traité a mis fin à la guerre de Cent Ans ?", answers: ["Arras", "traité d'Arras", "paix d'Arras"] }
    ]
    super_data.each do |attrs|
      QuizQuestion.find_or_create_by!(question: attrs[:question]) do |q|
        q.answers = attrs[:answers]
        q.difficulty = "rouge"
        q.question_type = "super_banco"
      end
    end
  end

  puts "Quiz: #{QuizQuestion.count} questions chargées (#{QuizQuestion.normal.count} normales, #{QuizQuestion.banco.count} banco, #{QuizQuestion.super_banco.count} super banco)"
end
