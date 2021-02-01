package proj756

import scala.concurrent.duration._

import io.gatling.core.Predef._
import io.gatling.http.Predef._

object Utility {
  /*
    Utility to get an Int from an environment variable.
    Return defInt if the environment var does not exist
    or cannot be converted to a string.
  */
  def envVarToInt(ev: String, defInt: Int): Int = {
    try {
      sys.env(ev).toInt
    } catch {
      case e: Exception => defInt
    }
  }

  /*
    Utility to get an environment variable.
    Return defStr if the environment var does not exist.
  */
  def envVar(ev: String, defStr: String): String = {
    sys.env.getOrElse(ev, defStr)
  }
}

object RMusic {

  val feeder = csv("music.csv").eager.random

  val rmusic = forever("i") {
    feed(feeder)
    .exec(http("RMusic")
      .get("/api/v1/music/${UUID}"))
      .pause(1)
  }

}

object RUser {

  val feeder = csv("users.csv").eager.circular

  val ruser = forever("i") {
    feed(feeder)
    .exec(http("RUser")
      .get("/api/v1/user/${UUID}"))
    .pause(1)
  }

}

/*
  Infinite loop that proceeds through all possible calls
  for the user table: create, login, logoff, read, update, delete.

  Note: Although the login call records the authorization token
  in ${user_id}, that value is not then used for the Authorization
  header.  A standard value is always passed instead (see class
  ReadTablesSim for the value).
*/
object AllUserCalls {

  val all_user_calls = forever("i") {
    exec(http("CreateUser")
      .post("/api/v1/user/")
      .body(StringBody(""" { "fname": "First${i}", "lname": "Last${i}", "email": "email${i}@sfu.ca" } """)).asJson
      .check(jsonPath("$..user_id").saveAs("user_id"))
      )
    .pause(1)

    .exec(http("LoginUser")
      .put("/api/v1/user/login")
      .body(StringBody(""" { "uid": "${user_id}" } """)).asJson
      .check(bodyString.saveAs("auth"))
      )
    .pause(1)

    .exec(http("LogoffUser")
      .put("/api/v1/user/logoff")
      .body(StringBody(""" { "jwt": "${auth}" } """)).asJson
      )
    .pause(1)

    .exec(http("ReadUser")
      .get("/api/v1/user/${user_id}")
      )
    .pause(1)

    .exec(http("UpdateUser")
      .put("/api/v1/user/${user_id}")
      .body(StringBody(""" { "fname": "First-up-${i}", "lname": "Last-up-${i}", "email": "email.up.${i}@sfu.ca" } """)).asJson
      )
    .pause(1)

    .exec(http("DeleteUser")
      .delete("/api/v1/user/${user_id}")
      )
    .pause(1)

  }

}

/*
  Infinite loop that proceeds through most calls
  for the music table: create, read, delete.

  Although a list_all call is also specified in the current
  code, it is not implemented and so is not called by this class.
*/
object AllMusicCalls {

  val all_music_calls = forever("i") {
    exec(http("CreateSong")
      .post("/api/v1/music/")
      .body(StringBody(""" { "Artist": "Artist${i}", "SongTitle": "Title${i}" } """)).asJson
      .check(jsonPath("$..music_id").saveAs("music_id"))
      )
    .pause(1)

    .exec(http("ReadSong")
      .get("/api/v1/music/${music_id}")
      )
    .pause(1)

    .exec(http("DeleteMusic")
      .delete("/api/v1/music/${music_id}")
      )
    .pause(1)

  }

}

/*
  After one S1 read, pause a random time between 1 and 60 s
*/
object RUserVarying {
  val feeder = csv("users.csv").eager.circular

  val ruser = forever("i") {
    feed(feeder)
    .exec(http("RUserVarying")
      .get("/api/v1/user/${UUID}"))
    .pause(1, 60)
  }
}

/*
  After one S2 read, pause a random time between 1 and 60 s
*/

object RMusicVarying {
  val feeder = csv("music.csv").eager.circular

  val rmusic = forever("i") {
    feed(feeder)
    .exec(http("RMusicVarying")
      .get("/api/v1/music/${UUID}"))
    .pause(1, 60)
  }
}

/*
  Failed attempt to interleave reads from User and Music tables.
  The Gatling EDSL only honours the second (Music) read,
  ignoring the first read of User. [Shrug-emoji] 
 */
object RBoth {

  val u_feeder = csv("users.csv").eager.circular
  val m_feeder = csv("music.csv").eager.random

  val rboth = forever("i") {
    feed(u_feeder)
    .exec(http("RUser ${i}")
      .get("/api/v1/user/${UUID}"))
    .pause(1);

    feed(m_feeder)
    .exec(http("RMusic ${i}")
      .get("/api/v1/music/${UUID}"))
      .pause(1)
  }

}

// Get Cluster IP from CLUSTER_IP environment variable or default to 127.0.0.1 (Minikube)
class ReadTablesSim extends Simulation {
  val httpProtocol = http
    .baseUrl("http://" + Utility.envVar("CLUSTER_IP", "127.0.0.1") + "/")
    .acceptHeader("application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
    .authorizationHeader("Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjoiZGJmYmMxYzAtMDc4My00ZWQ3LTlkNzgtMDhhYTRhMGNkYTAyIiwidGltZSI6MTYwNzM2NTU0NC42NzIwNTIxfQ.zL4i58j62q8mGUo5a0SQ7MHfukBUel8yl8jGT5XmBPo")
    .acceptLanguageHeader("en-US,en;q=0.5")
}

class ReadUserSim extends ReadTablesSim {
  val scnReadUser = scenario("ReadUser")
      .exec(RUser.ruser)

  setUp(
    scnReadUser.inject(atOnceUsers(Utility.envVarToInt("USERS", 1)))
  ).protocols(httpProtocol)
}

class ReadMusicSim extends ReadTablesSim {
  val scnReadMusic = scenario("ReadMusic")
    .exec(RMusic.rmusic)

  setUp(
    scnReadMusic.inject(atOnceUsers(Utility.envVarToInt("USERS", 1)))
  ).protocols(httpProtocol)
}

/*
  Run through all calls to the user service.
*/
class AllUserCalls extends ReadTablesSim {
  val scnAllUserCalls = scenario("AllUserCalls")
    .exec(AllUserCalls.all_user_calls)

  setUp(
    scnAllUserCalls.inject(atOnceUsers(Utility.envVarToInt("USERS", 1)))
  ).protocols(httpProtocol)
}

/*
  Run through all calls to the music service.
*/
class AllMusicCalls extends ReadTablesSim {
  val scnAllMusicCalls = scenario("AllMusicCalls")
    .exec(AllMusicCalls.all_music_calls)

  setUp(
    scnAllMusicCalls.inject(atOnceUsers(Utility.envVarToInt("USERS", 1)))
  ).protocols(httpProtocol)
}

/*
  Read both services concurrently at varying rates.
  Ramp up new users one / 10 s until requested USERS
  is reached for each service.
*/
class ReadBothVaryingSim extends ReadTablesSim {
  val scnReadMV = scenario("ReadMusicVarying")
    .exec(RMusicVarying.rmusic)

  val scnReadUV = scenario("ReadUserVarying")
    .exec(RUserVarying.ruser)

  val users = Utility.envVarToInt("USERS", 10)

  setUp(
    // Add one user per 10 s up to specified value
    scnReadMV.inject(rampConcurrentUsers(1).to(users).during(10*users)),
    scnReadUV.inject(rampConcurrentUsers(1).to(users).during(10*users))
  ).protocols(httpProtocol)
}

/*
  This doesn't work---it just reads the Music table.
  We left it in here as possible inspiration for other work
  (or a warning that this approach will fail).
 */
/*
class ReadBothSim extends ReadTablesSim {
  val scnReadBoth = scenario("ReadBoth")
    .exec(RBoth.rboth)

  setUp(
    scnReadBoth.inject(atOnceUsers(1))
  ).protocols(httpProtocol)
}
*/
