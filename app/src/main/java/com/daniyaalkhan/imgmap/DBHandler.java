package com.daniyaalkhan.imgmap;

import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.util.Log;

public class DBHandler extends SQLiteOpenHelper {

    public static final int DATABASE_VERSION = 1;
    public static final String DATABASE_NAME = "charts";
    private SQLiteDatabase db;

    public  DBHandler(Context context){
        super(context, DATABASE_NAME, null, DATABASE_VERSION);
    }

    @Override
    public void onCreate(SQLiteDatabase db){
        String[] queries = {
                "CREATE TABLE airports(id INTEGER PRIMARY KEY AUTOINCREMENT, icao VARCHAR(4));",
                "CREATE TABLE charts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, chart BLOB, cords1 DOUBLE, cords2 DOUBLE, pixel1 DOUBLE, pixel2 DOUBLE)"
        };

        for (String query:queries) {
            db.execSQL(query);
        }
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion){

    }

    public void addAirport(String icao){

        SQLiteDatabase db = getWritableDatabase();

        String query = "INSERT INTO airports(id, icao) VALUES(NULL, '"+icao+"')";
        db.execSQL(query);

    }

    public boolean getAirportExists(String icao){

        SQLiteDatabase db = getWritableDatabase();

        String query = "SELECT COUNT(*) FROM airports WHERE icao=?";
        Cursor cursor = db.rawQuery(query, new String[]{icao});

        cursor.moveToFirst();

        if(cursor.getInt(0)>0) return true;
        else return false;

    }
}
