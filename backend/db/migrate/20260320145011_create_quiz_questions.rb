class CreateQuizQuestions < ActiveRecord::Migration[7.2]
  def change
    create_table :quiz_questions do |t|
      t.text :question, null: false
      t.jsonb :answers, null: false, default: []
      t.string :difficulty, null: false  # bleu, blanc, rouge
      t.string :category                 # pour filtrage thématique
      t.string :question_type, default: "normal"  # normal, banco, super_banco

      t.timestamps
    end

    add_index :quiz_questions, :difficulty
    add_index :quiz_questions, :question_type
  end
end
