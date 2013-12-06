class StudentQuizController < ApplicationController
  def list
    @participant = AssignmentParticipant.find(params[:id])
    return unless current_user_id?(@participant.user_id)

    @assignment = @participant.assignment

    # Find the current phase that the assignment is in.
    @quiz_phase = @assignment.get_current_stage(AssignmentParticipant.find(params[:id]).topic_id)

    @quiz_mappings = QuizResponseMap.find_all_by_reviewer_id(@participant.id)

    # Calculate the number of quizzes that the user has completed so far.
    @num_quizzes_total = @quiz_mappings.size

    @num_quizzes_completed = 0
    @quiz_mappings.each do |map|
      @num_quizzes_completed += 1 if map.response
    end

    if @assignment.staggered_deadline?
      @quiz_mappings.each { |quiz_mapping|
        if @assignment.team_assignment?
          participant = AssignmentTeam.get_first_member(quiz_mapping.reviewee_id)
        else
          participant = quiz_mapping.reviewee
        end

        if !participant.nil? and !participant.topic_id.nil?
          quiz_due_date = TopicDeadline.find_by_topic_id_and_deadline_type_id(participant.topic_id,1)
        end
      }
      deadline_type_id = DeadlineType.find_by_name('quiz').id
    end
  end

  def finished_quiz
    #@response_map = ResponseMap.find_by_id(params[:map_id])
    @response = Response.find_by_map_id(params[:map_id])
  end

  def self.take_quiz assignment_id , reviewer_id
    @questionnaire = Array.new
    @assignment = Assignment.find_by_id(assignment_id)
    if @assignment.team_assignment?
      teams = TeamsUser.find_all_by_user_id(reviewer_id)
      Team.find_all_by_parent_id(assignment_id).each do |quiz_creator|
        unless TeamsUser.find_by_team_id(quiz_creator.id).user_id == reviewer_id
          Questionnaire.find_all_by_instructor_id(quiz_creator.id).each do |questionnaire|
            @questionnaire.push(questionnaire)
          end
        end
      end
    else
      Participant.find_all_by_parent_id(assignment_id).each do |quiz_creator|
        unless quiz_creator.user_id == reviewer_id
          Questionnaire.find_all_by_instructor_id(quiz_creator.id).each do |questionnaire|
            @questionnaire.push(questionnaire)
          end
        end
      end
    end
    return @questionnaire
  end
  def record_response
    @response = Response.new
    @map = QuizResponseMap.new
    @map.reviewee_id = Questionnaire.find_by_id(params[:questionnaire_id]).instructor_id
    @map.reviewer_id = Participant.find_by_user_id_and_parent_id(session[:user].id, params[:assignment_id]).id
    puts "HELLOOOOO"
    @map.reviewed_object_id = Questionnaire.find_by_instructor_id(@map.reviewee_id).id
    @map.save
    puts @map.id
    @response.map_id = @map.id
    @response.created_at = DateTime.current
    @response.updated_at = DateTime.current
    @response.save
    questions = Question.find_all_by_questionnaire_id params[:questionnaire_id]
    questions.each do |question|
      if (QuestionType.find_by_question_id question.id).q_type == 'MCC'
        params["#{question.id}"].each do |choice|
          new_response = Score.new :comments => choice, :question_id => question.id, :response_id => @response.id
          new_response.save
        end
      else
        new_response = Score.new :comments => params["#{question.id}"], :question_id => question.id, :response_id => @response.id
        new_response.save
      end

    end

    redirect_to :controller => 'student_quiz', :action => 'finished_quiz', :questionnaire_id => params[:questionnaire_id], :map_id => @map.id
  end
  def grade_essays
    #@question_types = QuestionType.find_all_by_q_type("Essay")
    #@questions = Array.new()
    #@question_types.each do |question_type|
    #  @questions << Question.find_by_id(question_type.question_id)
    #end
    @questionnaires = Array.new()
    @questionnaires = Questionnaire.find_all_by_type("QuizQuestionnaire")
    @questionnaire_questions = Hash.new()
    @questionnaires.each do |questionnaire|
      questions = Question.find_all_by_questionnaire_id(questionnaire.id)
      essay_questions = Array.new()
      questions.each do |question|
        if QuestionType.find_by_question_id(question.id).q_type == "Essay"
          essay_questions << question
        end
        #if question.questionnaire_id == questionnaire.id
        #if Question_Type.find_by_question_id(question.id).q_type == "Essay"
        #  essay_questions << question
        #end
        #end
      end
      @questionnaire_questions = @questionnaire_questions.merge({questionnaire.id => essay_questions})
    end


    @quiz_responses = Hash.new()
    @questionnaires.each do |questionnaire|
      @questionnaire_questions[questionnaire.id].each do |question|
        ungraded_quiz_responses = Array.new()
        quiz_responses = QuizResponse.find_all_by_question_id(question.id)
        quiz_responses.each do |response|
          if !graded?(response, question)
            ungraded_quiz_responses << response
          end
        end

        @quiz_responses = @quiz_responses.merge({question => ungraded_quiz_responses})
      end
    end


  end
  def graded?(response, question)
    if Score.find_by_question_id_and_response_id(question.id, response.id)
      return true
    else
      return false
    end
  end

  def record_response_old
    questions = Question.find_all_by_questionnaire_id params[:questionnaire_id]
    responses = Array.new
    valid = 0
    questions.each do |question|
      if (QuestionType.find_by_question_id question.id).q_type == 'MCC'
        if params["#{question.id}"] == nil
          valid = 1
        else
          params["#{question.id}"].each do |choice|
            new_response = QuizResponse.new :response => choice, :question_id => question.id, :questionnaire_id => params[:questionnaire_id], :participant_id => params[:participant_id], :assignment_id => params[:assignment_id]
            unless new_response.valid?
              valid = 1
            end
            responses.push(new_response)
          end
        end
      else
        new_response = QuizResponse.new :response => params["#{question.id}"], :question_id => question.id, :questionnaire_id => params[:questionnaire_id], :participant_id => params[:participant_id], :assignment_id => params[:assignment_id]
        unless new_response.valid?
          valid = 1
        end
        responses.push(new_response)
      end

    end

    if valid == 0
      responses.each do |response|
        response.save
      end
      #TODO send assignment id and participant id
      #TODO redirect to finished quiz view after this
      params.inspect
      redirect_to :controller => 'student_quiz', :action => 'finished_quiz', :questionnaire_id => params[:questionnaire_id]
    else
      flash[:error] = "Please answer every question."
      redirect_to :action => :take_quiz, :assignment_id => params[:assignment_id], :reviewer_id => session[:user].id, :questionnaire_id => params[:questionnaire_id]
    end
  end
end
